require "rails_helper"

RSpec.describe Documents::PromptBuilder do
  def context_result(context: "Trecho relevante do manual.", sources: [ :source_a, :source_b ])
    Documents::ContextBuilder::Result.new(
      context: context,
      sources: sources,
      chunks_count: sources.size,
      characters_count: context.to_s.length,
      truncated: false,
      input_chunks_count: sources.size,
      discarded_chunks_count: 0
    )
  end

  it "raises for a blank question" do
    expect do
      Documents::PromptBuilder.call(question: "   ", context_result: context_result)
    end.to raise_error(Documents::PromptBuilder::EmptyQuestionError)
  end

  it "raises when context_result is not a ContextBuilder::Result" do
    expect do
      Documents::PromptBuilder.call(question: "Qual o prazo?", context_result: { context: "x" })
    end.to raise_error(Documents::PromptBuilder::InvalidContextResultError)
  end

  it "raises when the context is blank" do
    expect do
      Documents::PromptBuilder.call(question: "Qual o prazo?", context_result: context_result(context: ""))
    end.to raise_error(Documents::PromptBuilder::EmptyContextError)
  end

  it "builds a system and user message embedding the context and the question" do
    result = Documents::PromptBuilder.call(
      question: "Qual o prazo da apólice?",
      context_result: context_result(context: "A apólice tem vigência de doze meses.")
    )

    expect(result.messages.size).to eq(2)
    expect(result.messages.first[:role]).to eq("system")
    expect(result.messages.last[:role]).to eq("user")
    expect(result.messages.last[:content]).to include("A apólice tem vigência de doze meses.")
    expect(result.messages.last[:content]).to include("Qual o prazo da apólice?")
    expect(result.context_included).to be_truthy
    expect(result.sources_count).to eq(2)
  end

  it "includes valid conversation history turns between the system and user messages" do
    history = [
      { role: "user", content: "primeira pergunta" },
      { "role" => "assistant", "content" => "primeira resposta" },
      { role: "narrator", content: "papel inválido, deve ser ignorado" },
      { role: "user", content: "   " }
    ]

    result = Documents::PromptBuilder.call(
      question: "Qual o prazo?",
      context_result: context_result,
      conversation_history: history
    )

    expect(result.messages.size).to eq(4)
    expect(result.messages.map { |message| message[:role] }).to eq(%w[system user assistant user])
    expect(result.messages[1][:content]).to eq("primeira pergunta")
    expect(result.messages[2][:content]).to eq("primeira resposta")
  end
end
