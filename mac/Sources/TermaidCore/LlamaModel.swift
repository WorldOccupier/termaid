import Foundation
import llama

/// Runs the fine-tuned GGUF in-process with llama.cpp, constrained to the reply grammar.
public actor LlamaModel: TextCompleting {
    // Prompt (~1k tokens with a long diagram so far) plus the longest allowed reply.
    private static let contextTokens: UInt32 = 4096
    // Matches MAX_REPLY_TOKENS in src/ollamaClient.ts.
    private static let maxReplyTokens = 1000

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let loopDetector: LoopDetector
    private var snapshot: PromptSnapshot?

    init(path: String, loopDetector: LoopDetector) throws {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 999
        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw EngineError(message: "could not load model at \(path)")
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = Self.contextTokens
        contextParams.n_batch = Self.contextTokens
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw EngineError(message: "could not create a llama.cpp context")
        }
        self.model = model
        self.context = context
        vocab = llama_model_get_vocab(model)
        self.loopDetector = loopDetector
    }

    public init(path: String) throws {
        try self.init(path: path, loopDetector: LoopDetector())
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    public func complete(system: String, user: String) throws -> String {
        let sampler = GrammarFirstSampler(vocab: vocab, grammar: ReplyGrammar.gbnf)
        try startFromSystemPrompt(system)
        try decode(tokenize(ChatPrompt.lfm3Tail(user: user), addingStart: false), failure: "read the prompt")
        return try generate(with: sampler)
    }

    /// Every call shares the long system prompt, so it is read once and restored from a snapshot
    /// afterwards, the way Ollama reuses it.
    private func startFromSystemPrompt(_ system: String) throws {
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)
        if let snapshot, snapshot.systemPrompt == system,
           llama_state_seq_set_data(context, snapshot.state, snapshot.state.count, 0) > 0 {
            return
        }
        llama_memory_clear(memory, true) // a failed restore can leave partial state behind
        try decode(tokenize(ChatPrompt.lfm3Head(system: system), addingStart: true), failure: "read the system prompt")
        var state = [UInt8](repeating: 0, count: llama_state_seq_get_size(context, 0))
        let savedBytes = llama_state_seq_get_data(context, &state, state.count, 0)
        snapshot = PromptSnapshot(systemPrompt: system, state: Array(state.prefix(savedBytes)))
    }

    private func decode(_ tokens: [llama_token], failure: String) throws {
        var tokens = tokens
        guard llama_decode(context, llama_batch_get_one(&tokens, Int32(tokens.count))) == 0 else {
            throw EngineError(message: "llama.cpp failed to \(failure)")
        }
    }

    private func generate(with sampler: GrammarFirstSampler) throws -> String {
        var reply = [CChar]()
        var replyTokens = [llama_token]()
        for _ in 0..<Self.maxReplyTokens {
            let token = sampler.sample(from: context)
            if llama_vocab_is_eog(vocab, token) { break }
            reply += piece(of: token)
            replyTokens.append(token)
            if loopDetector.isLooping(replyTokens) { break }
            try decode([token], failure: "generate")
        }
        return String(decoding: reply.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func tokenize(_ text: String, addingStart: Bool) -> [llama_token] {
        let byteCount = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(byteCount) + 8)
        let count = llama_tokenize(vocab, text, byteCount, &tokens, Int32(tokens.count), addingStart, true)
        return Array(tokens.prefix(Int(count)))
    }

    private func piece(of token: llama_token) -> [CChar] {
        var buffer = [CChar](repeating: 0, count: 64)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        return Array(buffer.prefix(Int(max(length, 0))))
    }
}
