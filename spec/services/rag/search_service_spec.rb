require "rails_helper"

# Rag::SearchService não recebe as colaborações (Ai::EmbeddingService) por
# injeção de dependência — chama Ai::EmbeddingService diretamente, então o
# caminho feliz exigiria rede real. O namespace Rag:: também não tem
# nenhuma referência fora de app/services/rag (grep confirmou), sugerindo
# que é código legado substituído por Documents::. Por isso só as
# validações (que não tocam a rede) são exercitadas aqui.
RSpec.describe Rag::SearchService do
  it "raises for a blank question" do
    expect do
      Rag::SearchService.call(question: "   ", limit: 3)
    end.to raise_error(Rag::SearchService::Error)
  end

  it "raises for a non-positive limit" do
    expect do
      Rag::SearchService.call(question: "Qual o prazo?", limit: 0)
    end.to raise_error(Rag::SearchService::Error)
  end
end
