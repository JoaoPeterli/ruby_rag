require "rails_helper"

# Documents::RetrievalPipelineService::STEPS é uma constante fixa (não é
# injetável) que inclui etapas que chamam LLM/embeddings de verdade
# (QueryExpansionStep, MultiQueryStep, EmbeddingStep, CrossEncoderRerankStep
# etc.), diferente de Documents::QuestionAnsweringService, que aceita
# retrieval_pipeline: como injeção. Isso significa que #call só é
# alcançável sem rede através das validações abaixo, que levantam erro
# antes de rodar o pipeline — o caminho feliz e o NoRelevantResultsError
# exigiriam uma chave de API real e não são exercitáveis aqui.
RSpec.describe Documents::RetrievalPipelineService do
  it "raises for a blank question" do
    expect do
      Documents::RetrievalPipelineService.call(question: "   ")
    end.to raise_error(Documents::RetrievalPipelineService::InvalidQuestionError)
  end

  it "raises for a non-positive search_limit" do
    expect do
      Documents::RetrievalPipelineService.call(question: "Qual o prazo?", search_limit: 0)
    end.to raise_error(Documents::RetrievalPipelineService::InvalidSearchLimitError)
  end

  it "raises when candidate_limit is smaller than search_limit" do
    expect do
      Documents::RetrievalPipelineService.call(question: "Qual o prazo?", search_limit: 10, candidate_limit: 5)
    end.to raise_error(Documents::RetrievalPipelineService::InvalidCandidateLimitError)
  end

  it "raises when minimum_similarity is out of range" do
    expect do
      Documents::RetrievalPipelineService.call(question: "Qual o prazo?", minimum_similarity: 1.5)
    end.to raise_error(Documents::RetrievalPipelineService::InvalidMinimumSimilarityError)
  end

  it "raises when mmr_lambda is out of range" do
    expect do
      Documents::RetrievalPipelineService.call(question: "Qual o prazo?", mmr_lambda: -0.1)
    end.to raise_error(Documents::RetrievalPipelineService::InvalidMmrLambdaError)
  end
end
