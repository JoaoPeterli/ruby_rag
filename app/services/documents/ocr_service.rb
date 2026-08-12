# frozen_string_literal: true

require "pdf/reader"
require "rtesseract"
require "tempfile"

module Documents
  # Extrai texto de um arquivo anexado (ActiveStorage) pra alimentar o
  # pipeline de ingestão que já existe (Documents::IngestionService,
  # que exige `text:` já pronto).
  #
  # Dois caminhos suportados nesta rodada:
  #
  # - PDF com camada de texto embutida (documento "digital", exportado
  #   de um sistema/Word) -- extraído via pdf-reader, sem OCR de
  #   verdade, rápido e sem dependência de sistema.
  # - Imagem solta (png/jpg/tiff) -- OCR de verdade via Tesseract
  #   (rtesseract).
  #
  # PDF escaneado sem camada de texto (precisaria rasterizar
  # página→imagem antes de rodar Tesseract) não é suportado ainda --
  # levanta UnsupportedFileError em vez de silenciosamente devolver
  # texto vazio/lixo.
  class OcrService
    IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/tiff].freeze
    MINIMUM_PDF_TEXT_LENGTH = 20

    Result = Data.define(:text, :engine, :duration_ms)

    class Error < StandardError; end
    class UnsupportedFileError < Error; end
    class ExtractionError < Error; end

    def self.call(...)
      new(...).call
    end

    def initialize(file:, pdf_text_extractor: PDF::Reader, image_ocr_engine: RTesseract)
      @file = file
      @pdf_text_extractor = pdf_text_extractor
      @image_ocr_engine = image_ocr_engine
    end

    def call
      started_at = monotonic_time

      text, engine = extract

      Result.new(
        text: text,
        engine: engine,
        duration_ms: elapsed_ms(started_at)
      )
    end

    private

    attr_reader :file, :pdf_text_extractor, :image_ocr_engine

    def extract
      case file.content_type
      when "application/pdf"
        [ extract_from_pdf, "pdf_text_layer" ]
      when *IMAGE_CONTENT_TYPES
        [ extract_from_image, "tesseract" ]
      else
        raise UnsupportedFileError, "Tipo de arquivo não suportado: #{file.content_type}"
      end
    end

    def extract_from_pdf
      text = download { |io| pdf_text_extractor.new(io).pages.map(&:text).join("\n\n") }.strip

      if text.length < MINIMUM_PDF_TEXT_LENGTH
        raise UnsupportedFileError,
              "O PDF não tem uma camada de texto extraível (provável scan). " \
              "Rasterização de página para OCR ainda não é suportada."
      end

      text
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => error
      raise ExtractionError, "Falha ao ler o PDF: #{error.message}"
    end

    def extract_from_image
      Tempfile.create([ "ocr-upload", extension_for(file.content_type) ]) do |tempfile|
        tempfile.binmode
        tempfile.write(file.download)
        tempfile.flush

        image_ocr_engine.new(tempfile.path).to_s.strip
      end
    rescue RTesseract::Error => error
      raise ExtractionError, "Falha ao rodar OCR na imagem: #{error.message}"
    end

    def download
      yield StringIO.new(file.download)
    end

    def extension_for(content_type)
      { "image/png" => ".png", "image/jpeg" => ".jpg", "image/tiff" => ".tiff" }.fetch(content_type, "")
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1_000).round(2)
    end
  end
end
