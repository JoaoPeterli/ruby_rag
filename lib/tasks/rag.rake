namespace :rag do
  desc "Executa uma busca semântica"
  task search: :environment do
    question = ENV.fetch("QUESTION")
    limit = ENV.fetch("LIMIT", 3).to_i

    results = Rag::SearchService.call(
      question: question,
      limit: limit
    )

    puts
    puts "Pergunta: #{question}"
    puts

    results.each_with_index do |chunk, index|
      puts "#{index + 1}. #{chunk.content}"
      puts "   Distância: #{chunk.neighbor_distance.round(4)}"
      puts "   Documento: #{chunk.document.title}"
      puts
    end
  end
end
