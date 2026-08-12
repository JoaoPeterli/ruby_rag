require "rails_helper"

RSpec.describe Rag::PromptBuilder do
  it "embeds the question and context and instructs a refusal when the answer is absent" do
    prompt = Rag::PromptBuilder.call(question: "Qual o prazo da apólice?", context: "Documento 1\n\nO prazo é de doze meses.")

    expect(prompt).to match("Qual o prazo da apólice?")
    expect(prompt).to match("O prazo é de doze meses.")
    expect(prompt).to match("Não encontrei essa informação na base de conhecimento.")
    expect(prompt.index("CONTEXTO")).to be < prompt.index("PERGUNTA")
  end
end
