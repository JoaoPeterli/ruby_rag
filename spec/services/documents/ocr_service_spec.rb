require "rails_helper"

RSpec.describe Documents::OcrService do
  let(:document) { create(:document, status: "uploaded", content: nil) }

  def attach(content_type:, filename:, body: "conteúdo qualquer")
    document.source_file.attach(io: StringIO.new(body), filename: filename, content_type: content_type)
    document.source_file
  end

  # Fakes injetados via pdf_text_extractor:/image_ocr_engine: -- não
  # depende do binário tesseract-ocr nem faz parsing de PDF de
  # verdade, só exercita o roteamento por content_type e o
  # tratamento de erro do próprio OcrService (a integração real com
  # os dois motores já foi validada manualmente com um PDF/imagem
  # reais).
  def fake_pdf_reader_class(&block)
    Class.new do
      define_singleton_method(:new) do |io|
        pages = block.call(io)
        Struct.new(:pages).new(pages.map { |text| Struct.new(:text).new(text) })
      end
    end
  end

  def fake_image_ocr_engine_class(&block)
    Class.new do
      define_singleton_method(:new) do |path|
        Struct.new(:to_s_result) do
          def to_s
            to_s_result
          end
        end.new(block.call(path))
      end
    end
  end

  it "extracts text from a PDF that already has a text layer" do
    file = attach(content_type: "application/pdf", filename: "apolice.pdf")
    pdf_reader = fake_pdf_reader_class { |_io| [ "Primeira página com bastante texto extraível de verdade." ] }

    result = Documents::OcrService.call(file: file, pdf_text_extractor: pdf_reader)

    expect(result.engine).to eq("pdf_text_layer")
    expect(result.text).to eq("Primeira página com bastante texto extraível de verdade.")
  end

  it "raises UnsupportedFileError when the PDF has no meaningful text layer (provável scan)" do
    file = attach(content_type: "application/pdf", filename: "scan.pdf")
    pdf_reader = fake_pdf_reader_class { |_io| [ "" ] }

    expect do
      Documents::OcrService.call(file: file, pdf_text_extractor: pdf_reader)
    end.to raise_error(Documents::OcrService::UnsupportedFileError)
  end

  it "wraps a malformed PDF as ExtractionError" do
    file = attach(content_type: "application/pdf", filename: "quebrado.pdf")
    raising_reader = Class.new do
      define_singleton_method(:new) { |_io| raise PDF::Reader::MalformedPDFError, "corrompido" }
    end

    expect do
      Documents::OcrService.call(file: file, pdf_text_extractor: raising_reader)
    end.to raise_error(Documents::OcrService::ExtractionError)
  end

  it "runs OCR on a supported image type" do
    file = attach(content_type: "image/png", filename: "pagina.png")
    ocr_engine = fake_image_ocr_engine_class { |_path| "  prazo de 5 dias  " }

    result = Documents::OcrService.call(file: file, image_ocr_engine: ocr_engine)

    expect(result.engine).to eq("tesseract")
    expect(result.text).to eq("prazo de 5 dias")
  end

  it "wraps a Tesseract failure as ExtractionError" do
    file = attach(content_type: "image/jpeg", filename: "pagina.jpg")
    raising_engine = Class.new do
      define_singleton_method(:new) { |_path| raise RTesseract::Error, "tesseract não encontrado" }
    end

    expect do
      Documents::OcrService.call(file: file, image_ocr_engine: raising_engine)
    end.to raise_error(Documents::OcrService::ExtractionError)
  end

  it "raises UnsupportedFileError for an unsupported content type" do
    file = attach(content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", filename: "arquivo.docx")

    expect do
      Documents::OcrService.call(file: file)
    end.to raise_error(Documents::OcrService::UnsupportedFileError)
  end
end
