// wsprobe: replicates the app's per-sentence model call (LFM3 chat prompt, greedy decoding under
// the reply grammar, LoopDetector) with llama.cpp, and optionally dumps per-token hidden states.
//
//   wsprobe <model.gguf> <requests.bin> <out.jsonl> [--force] [--dump DIR] [--names a,b] [--layers 0,5,..]
//
// requests.bin: records "system \x1f user \x1f forced_reply \x1e" (forced_reply only used with --force).
// gen mode: generates a reply per record. force mode: teacher-forces forced_reply and reports its
// per-token log-probs (no grammar). --dump writes DIR/<i>.f16: rows = positions predicting each reply
// token, cols = names x layers x n_embd (float16), plus DIR/<i>.json with the shape.
// Names: "l_out" (residual after layer) and "ffn" (= post_ffn_norm output, the MLP's write).
#include "llama.h"
#include "ggml.h"
#include "ggml-backend.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

static const char * GBNF = R"GBNF(
root ::= "{" ws "\"direction\"" ws ":" ws direction ws "," ws "\"boxes\"" ws ":" ws boxes ws "," ws "\"edges\"" ws ":" ws edges ws "}"
direction ::= "\"TD\"" | "\"LR\""
boxes ::= "[" ws ( string ( ws "," ws string )* )? ws "]"
edges ::= "[" ws ( edge ( ws "," ws edge )* )? ws "]"
edge ::= "[" ws string ws "," ws string ws "," ws string ws "]"
string ::= "\"" ( [^"\\\x7F\x00-\x1F] | "\\" ( ["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] ) )* "\""
ws ::= | " " | "\n" [ \t]{0,20}
)GBNF";

struct Capture {
    bool on = false;
    std::vector<std::string> names;   // graph tensor base names
    std::vector<int> layers;
    int n_embd = 0;
    // key "name-layer" -> columns appended in decode order (each column n_embd floats)
    std::map<std::string, std::vector<float>> data;
    std::map<std::string, int> wanted;
};

static std::string graph_name(const std::string & n) {
    if (n == "ffn") return "model.layers.{}.post_ffn_norm";
    if (n == "attn") return "model.layers.{}.post_operator_norm";
    return n;
}

static bool cb_eval(struct ggml_tensor * t, bool ask, void * ud) {
    auto * cap = (Capture *) ud;
    if (!cap->on) return false;
    const char * name = ggml_get_name(t);
    auto it = cap->wanted.find(name);
    if (ask) return it != cap->wanted.end();
    if (it == cap->wanted.end() || t->type != GGML_TYPE_F32 || t->ne[0] != cap->n_embd) return true;
    size_t n = ggml_nelements(t);
    auto & v = cap->data[name];
    size_t old = v.size();
    v.resize(old + n);
    ggml_backend_tensor_get(t, v.data() + old, 0, n * sizeof(float));
    return true;
}

static bool is_looping(const std::vector<llama_token> & toks) {
    const int shortest = 4, longest_cap = 64, repeats = 3;
    int longest = std::min(longest_cap, (int) toks.size() / repeats);
    for (int len = shortest; len <= longest; ++len) {
        bool all = true;
        for (int r = 1; r < repeats && all; ++r) {
            size_t end = toks.size() - r * len;
            for (int k = 0; k < len; ++k)
                if (toks[end - len + k] != toks[toks.size() - len + k]) { all = false; break; }
        }
        if (all) return true;
    }
    return false;
}

static std::vector<llama_token> tokenize(const llama_vocab * vocab, const std::string & s, bool add_special, bool parse_special) {
    std::vector<llama_token> t(s.size() + 8);
    int n = llama_tokenize(vocab, s.c_str(), (int) s.size(), t.data(), (int) t.size(), add_special, parse_special);
    t.resize(std::max(n, 0));
    return t;
}

static std::string piece(const llama_vocab * vocab, llama_token tok) {
    char buf[256];
    int n = llama_token_to_piece(vocab, tok, buf, sizeof buf, 0, false);
    return std::string(buf, std::max(n, 0));
}

static std::string json_escape(const std::string & s) {
    std::string o;
    for (unsigned char c : s) {
        if (c == '"') o += "\\\"";
        else if (c == '\\') o += "\\\\";
        else if (c == '\n') o += "\\n";
        else if (c == '\t') o += "\\t";
        else if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); o += b; }
        else o += (char) c;
    }
    return o;
}

static bool decode(llama_context * ctx, std::vector<llama_token> & toks, int pos0, bool all_logits) {
    llama_batch b = llama_batch_init((int) toks.size(), 0, 1);
    for (size_t i = 0; i < toks.size(); ++i) {
        b.token[i] = toks[i];
        b.pos[i] = pos0 + (int) i;
        b.n_seq_id[i] = 1;
        b.seq_id[i][0] = 0;
        b.logits[i] = all_logits || i + 1 == toks.size();
    }
    b.n_tokens = (int) toks.size();
    int rc = llama_decode(ctx, b);
    llama_batch_free(b);
    return rc == 0;
}

// Greedy under the grammar, checking the free pick first (GrammarFirstSampler.swift).
static llama_token sample(llama_sampler * grammar, const float * logits, int n_vocab, std::vector<llama_token_data> & cand) {
    int best = 0;
    for (int i = 1; i < n_vocab; ++i) if (logits[i] > logits[best]) best = i;
    llama_token_data one = {best, logits[best], 0};
    llama_token_data_array arr1 = {&one, 1, -1, false};
    llama_sampler_apply(grammar, &arr1);
    if (std::isfinite(one.logit)) return best;
    for (int i = 0; i < n_vocab; ++i) cand[i] = {i, logits[i], 0};
    llama_token_data_array arr = {cand.data(), (size_t) n_vocab, -1, false};
    llama_sampler_apply(grammar, &arr);
    int b = -1;
    for (int i = 0; i < n_vocab; ++i)
        if (std::isfinite(cand[i].logit) && (b < 0 || cand[i].logit > cand[b].logit)) b = i;
    return cand[b].id;
}

int main(int argc, char ** argv) {
    if (argc < 4) { fprintf(stderr, "usage: wsprobe model requests.bin out.jsonl [--force] [--dump DIR] [--names l_out,ffn] [--layers 0,1,..]\n"); return 2; }
    std::string model_path = argv[1], req_path = argv[2], out_path = argv[3], dump_dir;
    bool force = false;
    Capture cap;
    cap.names = {"l_out"};
    for (int i = 4; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--force") force = true;
        else if (a == "--dump") dump_dir = argv[++i];
        else if (a == "--names") { cap.names.clear(); std::stringstream ss(argv[++i]); std::string x; while (std::getline(ss, x, ',')) cap.names.push_back(x); }
        else if (a == "--layers") { std::stringstream ss(argv[++i]); std::string x; while (std::getline(ss, x, ',')) cap.layers.push_back(std::stoi(x)); }
    }

    llama_log_set([](ggml_log_level, const char *, void *) {}, nullptr);
    llama_backend_init();
    auto mp = llama_model_default_params();
    mp.n_gpu_layers = 999;
    llama_model * model = llama_model_load_from_file(model_path.c_str(), mp);
    if (!model) { fprintf(stderr, "load failed\n"); return 1; }
    const llama_vocab * vocab = llama_model_get_vocab(model);
    int n_vocab = llama_vocab_n_tokens(vocab);
    cap.n_embd = llama_model_n_embd(model);
    if (cap.layers.empty()) for (int l = 0; l < llama_model_n_layer(model); ++l) cap.layers.push_back(l);
    for (auto & n : cap.names) for (int l : cap.layers) cap.wanted[graph_name(n) + "-" + std::to_string(l)] = 1;

    auto cp = llama_context_default_params();
    cp.n_ctx = 4096; cp.n_batch = 4096; cp.n_ubatch = 4096;
    if (!dump_dir.empty()) { cp.cb_eval = cb_eval; cp.cb_eval_user_data = &cap; }
    llama_context * ctx = llama_init_from_model(model, cp);
    if (!ctx) { fprintf(stderr, "context failed\n"); return 1; }

    // "-" streams records from stdin (one reply line per record, flushed), for interactive drivers.
    bool streaming = req_path == "-";
    std::vector<std::string> records;
    if (!streaming) {
        std::ifstream in(req_path, std::ios::binary);
        std::string all((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        std::string cur; for (char c : all) { if (c == '\x1e') { records.push_back(cur); cur.clear(); } else cur += c; }
    }
    auto next_record = [&](size_t ri, std::string & rec) -> bool {
        if (!streaming) { if (ri >= records.size()) return false; rec = records[ri]; return true; }
        rec.clear(); int c;
        while ((c = getchar()) != EOF) { if (c == '\x1e') return true; rec += (char) c; }
        return false;
    };
    FILE * out = out_path == "-" ? stdout : fopen(out_path.c_str(), "w");
    std::vector<llama_token_data> cand(n_vocab);

    std::string rec;
    for (size_t ri = 0; next_record(ri, rec); ++ri) {
        std::vector<std::string> f; { std::string cur; for (char c : rec) { if (c == '\x1f') { f.push_back(cur); cur.clear(); } else cur += c; } f.push_back(cur); }
        const std::string & sys = f[0], & user = f[1];
        std::string head = "<|im_start|>system\n" + sys + "<|im_end|>\n<|im_start|>user\n";
        std::string tail = user + "<|im_end|>\n<|im_start|>assistant\n<think></think>";
        llama_memory_clear(llama_get_memory(ctx), true);
        cap.data.clear();
        auto ht = tokenize(vocab, head, true, true);
        auto tt = tokenize(vocab, tail, false, true);
        std::vector<llama_token> prompt = ht; prompt.insert(prompt.end(), tt.begin(), tt.end());
        int np = (int) prompt.size();
        std::string reply; std::vector<llama_token> rtoks; bool looped = false, maxed = false;
        std::vector<float> lps; std::vector<int> argmax_match, offsets, keep_rows;
        // capture only the positions predicting reply tokens
        int skip_cols = 0;  // per tensor, columns before the first wanted position
        if (!force) {
            // Head without capture, tail with capture (we keep the last column of each tensor).
            cap.on = false;
            if (!decode(ctx, ht, 0, false)) { fprintf(stderr, "decode failed\n"); return 1; }
            cap.on = !dump_dir.empty();
            if (!decode(ctx, tt, (int) ht.size(), false)) { fprintf(stderr, "decode failed\n"); return 1; }
            // keep last column only
            for (auto & [k, v] : cap.data) { std::vector<float> last(v.end() - cap.n_embd, v.end()); v = last; }
            llama_sampler * grammar = llama_sampler_init_grammar(vocab, GBNF, "root");
            int pos = np;
            for (int step = 0; step < 1000; ++step) {
                const float * logits = llama_get_logits_ith(ctx, -1);
                llama_token tok = sample(grammar, logits, n_vocab, cand);
                llama_sampler_accept(grammar, tok);
                if (llama_vocab_is_eog(vocab, tok)) break;
                reply += piece(vocab, tok); rtoks.push_back(tok);
                if (is_looping(rtoks)) { looped = true; break; }
                if (step == 999) { maxed = true; break; }
                std::vector<llama_token> one = {tok};
                if (!decode(ctx, one, pos++, false)) { fprintf(stderr, "decode failed\n"); return 1; }
            }
            llama_sampler_free(grammar);
            cap.on = false;
        } else {
            rtoks = tokenize(vocab, f.size() > 2 ? f[2] : "", false, false);
            std::vector<llama_token> seq = prompt; seq.insert(seq.end(), rtoks.begin(), rtoks.end());
            cap.on = !dump_dir.empty();
            cap.data.clear();
            if (!decode(ctx, seq, 0, true)) { fprintf(stderr, "decode failed (len %zu)\n", seq.size()); return 1; }
            cap.on = false;
            for (size_t k = 0; k < rtoks.size(); ++k) {
                const float * lg = llama_get_logits_ith(ctx, np - 1 + (int) k);
                float mx = lg[0]; int am = 0;
                for (int i = 1; i < n_vocab; ++i) if (lg[i] > mx) { mx = lg[i]; am = i; }
                double s = 0; for (int i = 0; i < n_vocab; ++i) s += std::exp((double) lg[i] - mx);
                lps.push_back((float) (lg[rtoks[k]] - mx - std::log(s)));
                argmax_match.push_back(am == rtoks[k]);
                reply += piece(vocab, rtoks[k]);
            }
            skip_cols = np - 1;
            size_t off = 0;
            for (size_t k = 0; k < rtoks.size(); ++k) { offsets.push_back((int) off); off += piece(vocab, rtoks[k]).size(); }
            // optional 4th field: byte offsets in the reply; keep only rows predicting the tokens covering them
            if (f.size() > 3 && !f[3].empty()) {
                std::stringstream ss(f[3]); std::string x;
                while (std::getline(ss, x, ',')) {
                    int o = std::stoi(x), k = 0;
                    while (k + 1 < (int) offsets.size() && offsets[k + 1] <= o) ++k;
                    keep_rows.push_back(k);
                }
            }
        }
        fprintf(out, "{\"i\":%zu,\"prompt_tokens\":%d,\"ntok\":%zu,\"looped\":%s,\"maxed\":%s,\"reply\":\"%s\"",
                ri, np, rtoks.size(), looped ? "true" : "false", maxed ? "true" : "false", json_escape(reply).c_str());
        fprintf(out, ",\"tokens\":[");
        for (size_t k = 0; k < rtoks.size(); ++k) fprintf(out, "%s%d", k ? "," : "", rtoks[k]);
        fprintf(out, "]");
        if (force) {
            fprintf(out, ",\"logprobs\":[");
            for (size_t k = 0; k < lps.size(); ++k) fprintf(out, "%s%.4f", k ? "," : "", lps[k]);
            fprintf(out, "],\"argmax\":[");
            for (size_t k = 0; k < argmax_match.size(); ++k) fprintf(out, "%s%d", k ? "," : "", argmax_match[k]);
            fprintf(out, "],\"offsets\":[");
            for (size_t k = 0; k < offsets.size(); ++k) fprintf(out, "%s%d", k ? "," : "", offsets[k]);
            fprintf(out, "],\"rows\":[");
            for (size_t k = 0; k < keep_rows.size(); ++k) fprintf(out, "%s%d", k ? "," : "", keep_rows[k]);
            fprintf(out, "]");
        }
        fprintf(out, "}\n");
        fflush(out);
        if (!dump_dir.empty()) {
            // gen: row k predicts token k; force: same, or only keep_rows when given
            std::vector<int> row_ids;
            if (!keep_rows.empty()) row_ids = keep_rows; else for (size_t k = 0; k < rtoks.size(); ++k) row_ids.push_back((int) k);
            int rows = (int) row_ids.size();
            std::vector<std::string> keys;
            for (auto & n : cap.names) for (int l : cap.layers) keys.push_back(graph_name(n) + "-" + std::to_string(l));
            std::vector<ggml_fp16_t> buf((size_t) rows * keys.size() * cap.n_embd);
            for (int r = 0; r < rows; ++r)
                for (size_t ki = 0; ki < keys.size(); ++ki) {
                    auto & v = cap.data[keys[ki]];
                    size_t col = (size_t) (skip_cols + row_ids[r]);
                    const float * src = (col + 1) * cap.n_embd <= v.size() ? v.data() + col * cap.n_embd : nullptr;
                    for (int e = 0; e < cap.n_embd; ++e)
                        buf[((size_t) r * keys.size() + ki) * cap.n_embd + e] = ggml_fp32_to_fp16(src ? src[e] : NAN);
                }
            std::string p = dump_dir + "/" + std::to_string(ri) + ".f16";
            FILE * df = fopen(p.c_str(), "wb");
            fwrite(buf.data(), sizeof(ggml_fp16_t), buf.size(), df);
            fclose(df);
            std::ofstream js(dump_dir + "/" + std::to_string(ri) + ".json");
            js << "{\"rows\":" << rows << ",\"keys\":[";
            for (size_t ki = 0; ki < keys.size(); ++ki) js << (ki ? "," : "") << "\"" << json_escape(keys[ki]) << "\"";
            js << "],\"n_embd\":" << cap.n_embd << "}";
        }
    }
    if (out != stdout) fclose(out);
    llama_free(ctx);
    llama_model_free(model);
    return 0;
}
