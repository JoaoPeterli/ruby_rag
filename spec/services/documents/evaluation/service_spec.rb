require "rails_helper"

RSpec.describe Documents::Evaluation::Service do
  def fake_answer_result_class
    @fake_answer_result_class ||= Struct.new(:answer)
  end

  it "creates a run, persists a result per case and summarizes the averages" do
    case_one = create(:rag_eval_case, question: "pergunta 1", expected_answer: "resposta 1")
    case_two = create(:rag_eval_case, question: "pergunta 2", expected_answer: "resposta 2")

    answer_result_class = fake_answer_result_class
    fake_question_answering_service = Class.new do
      define_singleton_method(:call) { |**_kwargs| answer_result_class.new("resposta gerada") }
    end

    metrics_by_case = {
      case_one.id => Documents::Evaluation::Metrics.new(
        retrieval_precision: 1.0, retrieval_recall: 1.0, chunk_relevance: 0.9,
        answer_faithfulness: 0.8, citation_coverage: 1.0, no_evidence_correct: true
      ),
      case_two.id => Documents::Evaluation::Metrics.new(
        retrieval_precision: 0.0, retrieval_recall: 0.0, chunk_relevance: 0.5,
        answer_faithfulness: 0.6, citation_coverage: 0.0, no_evidence_correct: false
      )
    }

    fake_metrics_calculator = Class.new do
      define_singleton_method(:call) do |eval_case:, answer_result:|
        metrics_by_case.fetch(eval_case.id)
      end
    end

    run = Documents::Evaluation::Service.call(
      cases: RagEvalCase.where(id: [ case_one.id, case_two.id ]),
      question_answering_service: fake_question_answering_service,
      metrics_calculator: fake_metrics_calculator
    )

    expect(run.persisted?).to be_truthy
    expect(run.rag_eval_results.count).to eq(2)
    expect(run.summary["cases_count"]).to eq(2)
    expect(run.summary["errored_count"]).to eq(0)
    expect(run.summary["retrieval_precision"]).to be_within(0.0001).of(0.5)
    # no_evidence_accuracy usa filter_map sobre um booleano: um resultado
    # `false` é descartado (não vira 0) em vez de contar como erro, então
    # aqui só o caso `true` entra na média — resultado 1.0, não 0.5.
    expect(run.summary["no_evidence_accuracy"]).to be_within(0.0001).of(1.0)
  end

  it "records a failed case without stopping the run when the answering service raises" do
    ok_case = create(:rag_eval_case, question: "pergunta ok", expected_answer: "resposta")
    broken_case = create(:rag_eval_case, question: "pergunta quebrada", expected_answer: "resposta")

    fake_metrics = Documents::Evaluation::Metrics.new(
      retrieval_precision: 1.0, retrieval_recall: 1.0, chunk_relevance: 1.0,
      answer_faithfulness: 1.0, citation_coverage: 1.0, no_evidence_correct: true
    )

    answer_result_class = fake_answer_result_class
    fake_question_answering_service = Class.new do
      define_singleton_method(:call) do |question:, **_kwargs|
        raise "explodiu" if question == "pergunta quebrada"

        answer_result_class.new("resposta gerada")
      end
    end

    fake_metrics_calculator = Class.new do
      define_singleton_method(:call) { |**_kwargs| fake_metrics }
    end

    run = Documents::Evaluation::Service.call(
      cases: RagEvalCase.where(id: [ ok_case.id, broken_case.id ]),
      question_answering_service: fake_question_answering_service,
      metrics_calculator: fake_metrics_calculator
    )

    expect(run.rag_eval_results.count).to eq(2)
    expect(run.summary["errored_count"]).to eq(1)

    failed_result = run.rag_eval_results.find_by(rag_eval_case_id: broken_case.id)
    expect(failed_result.errored).to be_truthy
    expect(failed_result.error_message).to match(/explodiu/)
  end
end
