import Accelerate
import llama

/// Picks the highest-scoring token, the way llama.cpp's own CLI handles grammars: check the free
/// pick first, and only run the (slow) grammar over the whole vocabulary when it breaks the
/// grammar. Most picks already fit, so most tokens cost one grammar check instead of 65k.
final class GrammarFirstSampler {
    private let grammar: UnsafeMutablePointer<llama_sampler>
    private let greedy: UnsafeMutablePointer<llama_sampler>
    private let vocabularySize: Int
    private var candidates: [llama_token_data]

    init(vocab: OpaquePointer, grammar gbnf: String) {
        grammar = llama_sampler_init_grammar(vocab, gbnf, "root")
        greedy = llama_sampler_init_greedy()
        vocabularySize = Int(llama_vocab_n_tokens(vocab))
        candidates = [llama_token_data](repeating: llama_token_data(), count: vocabularySize)
    }

    deinit {
        llama_sampler_free(grammar)
        llama_sampler_free(greedy)
    }

    func sample(from context: OpaquePointer) -> llama_token {
        let logits = llama_get_logits_ith(context, -1)!
        var token = highestScoring(in: logits)
        if !grammarAllows(token, logit: logits[Int(token)]) {
            token = highestScoringAllowed(in: logits)
        }
        llama_sampler_accept(grammar, token)
        return token
    }

    private func highestScoring(in logits: UnsafeMutablePointer<Float>) -> llama_token {
        var maximum: Float = 0
        var index: vDSP_Length = 0
        vDSP_maxvi(logits, 1, &maximum, &index, vDSP_Length(vocabularySize))
        return llama_token(index)
    }

    private func highestScoringAllowed(in logits: UnsafeMutablePointer<Float>) -> llama_token {
        for id in 0..<vocabularySize {
            candidates[id] = llama_token_data(id: llama_token(id), logit: logits[id], p: 0)
        }
        return candidates.withUnsafeMutableBufferPointer { buffer in
            var array = llama_token_data_array(data: buffer.baseAddress, size: buffer.count, selected: -1, sorted: false)
            llama_sampler_apply(grammar, &array)
            llama_sampler_apply(greedy, &array)
            return array.data[Int(array.selected)].id
        }
    }

    private func grammarAllows(_ token: llama_token, logit: Float) -> Bool {
        var single = llama_token_data(id: token, logit: logit, p: 0)
        var array = llama_token_data_array(data: &single, size: 1, selected: -1, sorted: false)
        llama_sampler_apply(grammar, &array)
        return single.logit.isFinite
    }
}
