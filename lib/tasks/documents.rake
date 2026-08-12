# frozen_string_literal: true

namespace :documents do
  desc "Marca como 'failed' documentos presos em 'processing' (worker morto/job perdido)"
  task reconcile_stale_processing: :environment do
    reconciled = Documents::ReconcileStaleProcessingDocumentsService.call

    if reconciled.empty?
      puts "Nenhum documento preso em 'processing' encontrado."
    else
      puts "#{reconciled.size} documento(s) movido(s) de 'processing' para 'failed': " \
           "#{reconciled.map { |item| item[:document_id] }.join(', ')}"
    end
  end
end
