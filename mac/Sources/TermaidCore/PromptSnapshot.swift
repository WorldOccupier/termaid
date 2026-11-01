/// llama.cpp's state right after reading one system prompt. LFM is a hybrid model whose
/// convolution state can't be partly rewound, so the whole state is saved and restored instead.
struct PromptSnapshot {
    let systemPrompt: String
    let state: [UInt8]
}
