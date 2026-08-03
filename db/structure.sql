--
-- PostgreSQL database dump
--

\restrict lgOOMUBZzhWm5BKYhQpFyNwpmZr54hChEblhuzJhJcyBfOin8RPKKPuVuihgyas

-- Dumped from database version 16.14 (Debian 16.14-1.pgdg12+1)
-- Dumped by pg_dump version 16.14 (Debian 16.14-1.pgdg12+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: document_chunks_search_vector_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.document_chunks_search_vector_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.search_vector :=
    to_tsvector(
      'portuguese',
      COALESCE(NEW.content, '')
    );

  RETURN NEW;
END
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    name character varying NOT NULL,
    api_key character varying NOT NULL,
    operator boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: document_chunks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_chunks (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    content text NOT NULL,
    "position" integer NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    embedding public.vector(1536),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    content_hash character varying NOT NULL,
    search_vector tsvector NOT NULL,
    account_id bigint
);


--
-- Name: document_chunks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.document_chunks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: document_chunks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.document_chunks_id_seq OWNED BY public.document_chunks.id;


--
-- Name: documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documents (
    id bigint NOT NULL,
    title character varying NOT NULL,
    source character varying,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    content text,
    ramo character varying,
    seguradora character varying,
    cliente character varying,
    tipo_documento character varying,
    vigencia_ano integer,
    content_hash character varying,
    content_version integer DEFAULT 1 NOT NULL,
    account_id bigint
);


--
-- Name: documents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.documents_id_seq OWNED BY public.documents.id;


--
-- Name: rag_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rag_answers (
    id bigint NOT NULL,
    rag_query_id bigint NOT NULL,
    answer text NOT NULL,
    model character varying,
    grounded boolean,
    refused boolean,
    citation_coverage double precision,
    hallucination_rate double precision,
    confidence_score double precision,
    confidence_level character varying,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rag_answers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rag_answers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rag_answers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rag_answers_id_seq OWNED BY public.rag_answers.id;


--
-- Name: rag_eval_cases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rag_eval_cases (
    id bigint NOT NULL,
    question text NOT NULL,
    expected_answer text,
    expected_chunk_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    expected_document_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    category character varying,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    account_id bigint
);


--
-- Name: rag_eval_cases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rag_eval_cases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rag_eval_cases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rag_eval_cases_id_seq OWNED BY public.rag_eval_cases.id;


--
-- Name: rag_eval_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rag_eval_results (
    id bigint NOT NULL,
    rag_eval_run_id bigint NOT NULL,
    rag_eval_case_id bigint NOT NULL,
    answer text,
    metrics jsonb DEFAULT '{}'::jsonb NOT NULL,
    duration_ms integer,
    errored boolean DEFAULT false NOT NULL,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rag_eval_results_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rag_eval_results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rag_eval_results_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rag_eval_results_id_seq OWNED BY public.rag_eval_results.id;


--
-- Name: rag_eval_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rag_eval_runs (
    id bigint NOT NULL,
    cases_count integer DEFAULT 0 NOT NULL,
    summary jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rag_eval_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rag_eval_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rag_eval_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rag_eval_runs_id_seq OWNED BY public.rag_eval_runs.id;


--
-- Name: rag_feedbacks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rag_feedbacks (
    id bigint NOT NULL,
    rag_answer_id bigint NOT NULL,
    rating character varying NOT NULL,
    reason text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rag_feedbacks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rag_feedbacks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rag_feedbacks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rag_feedbacks_id_seq OWNED BY public.rag_feedbacks.id;


--
-- Name: rag_queries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rag_queries (
    id bigint NOT NULL,
    question text NOT NULL,
    normalized_question text,
    search_query text,
    status character varying DEFAULT 'completed'::character varying NOT NULL,
    duration_ms integer,
    total_tokens integer,
    metrics jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    cache_hit boolean DEFAULT false NOT NULL,
    account_id bigint
);


--
-- Name: rag_queries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rag_queries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rag_queries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rag_queries_id_seq OWNED BY public.rag_queries.id;


--
-- Name: rag_retrieval_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rag_retrieval_results (
    id bigint NOT NULL,
    rag_query_id bigint NOT NULL,
    document_chunk_id bigint,
    "position" integer,
    cited boolean DEFAULT false NOT NULL,
    hybrid_score double precision,
    rerank_score double precision,
    cross_encoder_score double precision,
    combined_score double precision,
    mmr_score double precision,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rag_retrieval_results_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rag_retrieval_results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rag_retrieval_results_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rag_retrieval_results_id_seq OWNED BY public.rag_retrieval_results.id;


--
-- Name: rag_semantic_cache_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rag_semantic_cache_entries (
    id bigint NOT NULL,
    question text NOT NULL,
    question_embedding public.vector(1536) NOT NULL,
    answer text NOT NULL,
    sources jsonb DEFAULT '[]'::jsonb NOT NULL,
    model character varying,
    confidence_score double precision,
    confidence_level character varying,
    hits integer DEFAULT 0 NOT NULL,
    last_hit_at timestamp(6) without time zone,
    expires_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    account_id bigint
);


--
-- Name: rag_semantic_cache_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rag_semantic_cache_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rag_semantic_cache_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rag_semantic_cache_entries_id_seq OWNED BY public.rag_semantic_cache_entries.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: document_chunks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_chunks ALTER COLUMN id SET DEFAULT nextval('public.document_chunks_id_seq'::regclass);


--
-- Name: documents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents ALTER COLUMN id SET DEFAULT nextval('public.documents_id_seq'::regclass);


--
-- Name: rag_answers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_answers ALTER COLUMN id SET DEFAULT nextval('public.rag_answers_id_seq'::regclass);


--
-- Name: rag_eval_cases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_eval_cases ALTER COLUMN id SET DEFAULT nextval('public.rag_eval_cases_id_seq'::regclass);


--
-- Name: rag_eval_results id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_eval_results ALTER COLUMN id SET DEFAULT nextval('public.rag_eval_results_id_seq'::regclass);


--
-- Name: rag_eval_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_eval_runs ALTER COLUMN id SET DEFAULT nextval('public.rag_eval_runs_id_seq'::regclass);


--
-- Name: rag_feedbacks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_feedbacks ALTER COLUMN id SET DEFAULT nextval('public.rag_feedbacks_id_seq'::regclass);


--
-- Name: rag_queries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_queries ALTER COLUMN id SET DEFAULT nextval('public.rag_queries_id_seq'::regclass);


--
-- Name: rag_retrieval_results id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_retrieval_results ALTER COLUMN id SET DEFAULT nextval('public.rag_retrieval_results_id_seq'::regclass);


--
-- Name: rag_semantic_cache_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_semantic_cache_entries ALTER COLUMN id SET DEFAULT nextval('public.rag_semantic_cache_entries_id_seq'::regclass);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: document_chunks document_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_chunks
    ADD CONSTRAINT document_chunks_pkey PRIMARY KEY (id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: rag_answers rag_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_answers
    ADD CONSTRAINT rag_answers_pkey PRIMARY KEY (id);


--
-- Name: rag_eval_cases rag_eval_cases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_eval_cases
    ADD CONSTRAINT rag_eval_cases_pkey PRIMARY KEY (id);


--
-- Name: rag_eval_results rag_eval_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_eval_results
    ADD CONSTRAINT rag_eval_results_pkey PRIMARY KEY (id);


--
-- Name: rag_eval_runs rag_eval_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_eval_runs
    ADD CONSTRAINT rag_eval_runs_pkey PRIMARY KEY (id);


--
-- Name: rag_feedbacks rag_feedbacks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_feedbacks
    ADD CONSTRAINT rag_feedbacks_pkey PRIMARY KEY (id);


--
-- Name: rag_queries rag_queries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_queries
    ADD CONSTRAINT rag_queries_pkey PRIMARY KEY (id);


--
-- Name: rag_retrieval_results rag_retrieval_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_retrieval_results
    ADD CONSTRAINT rag_retrieval_results_pkey PRIMARY KEY (id);


--
-- Name: rag_semantic_cache_entries rag_semantic_cache_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_semantic_cache_entries
    ADD CONSTRAINT rag_semantic_cache_entries_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: index_accounts_on_api_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_api_key ON public.accounts USING btree (api_key);


--
-- Name: index_document_chunks_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_chunks_on_account_id ON public.document_chunks USING btree (account_id);


--
-- Name: index_document_chunks_on_document_and_content_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_document_chunks_on_document_and_content_hash ON public.document_chunks USING btree (document_id, content_hash);


--
-- Name: index_document_chunks_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_chunks_on_document_id ON public.document_chunks USING btree (document_id);


--
-- Name: index_document_chunks_on_document_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_document_chunks_on_document_id_and_position ON public.document_chunks USING btree (document_id, "position");


--
-- Name: index_document_chunks_on_embedding_hnsw; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_chunks_on_embedding_hnsw ON public.document_chunks USING hnsw (embedding public.vector_cosine_ops);


--
-- Name: index_document_chunks_on_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_chunks_on_search_vector ON public.document_chunks USING gin (search_vector);


--
-- Name: index_documents_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_account_id ON public.documents USING btree (account_id);


--
-- Name: index_documents_on_cliente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_cliente ON public.documents USING btree (cliente);


--
-- Name: index_documents_on_content_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_content_hash ON public.documents USING btree (content_hash);


--
-- Name: index_documents_on_metadata; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_metadata ON public.documents USING gin (metadata);


--
-- Name: index_documents_on_ramo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_ramo ON public.documents USING btree (ramo);


--
-- Name: index_documents_on_seguradora; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_seguradora ON public.documents USING btree (seguradora);


--
-- Name: index_documents_on_tipo_documento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_tipo_documento ON public.documents USING btree (tipo_documento);


--
-- Name: index_documents_on_vigencia_ano; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_vigencia_ano ON public.documents USING btree (vigencia_ano);


--
-- Name: index_rag_answers_on_confidence_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_answers_on_confidence_level ON public.rag_answers USING btree (confidence_level);


--
-- Name: index_rag_answers_on_rag_query_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_answers_on_rag_query_id ON public.rag_answers USING btree (rag_query_id);


--
-- Name: index_rag_eval_cases_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_eval_cases_on_account_id ON public.rag_eval_cases USING btree (account_id);


--
-- Name: index_rag_eval_cases_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_eval_cases_on_active ON public.rag_eval_cases USING btree (active);


--
-- Name: index_rag_eval_cases_on_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_eval_cases_on_category ON public.rag_eval_cases USING btree (category);


--
-- Name: index_rag_eval_results_on_rag_eval_case_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_eval_results_on_rag_eval_case_id ON public.rag_eval_results USING btree (rag_eval_case_id);


--
-- Name: index_rag_eval_results_on_rag_eval_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_eval_results_on_rag_eval_run_id ON public.rag_eval_results USING btree (rag_eval_run_id);


--
-- Name: index_rag_feedbacks_on_rag_answer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_feedbacks_on_rag_answer_id ON public.rag_feedbacks USING btree (rag_answer_id);


--
-- Name: index_rag_feedbacks_on_rating; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_feedbacks_on_rating ON public.rag_feedbacks USING btree (rating);


--
-- Name: index_rag_queries_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_queries_on_account_id ON public.rag_queries USING btree (account_id);


--
-- Name: index_rag_queries_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_queries_on_created_at ON public.rag_queries USING btree (created_at);


--
-- Name: index_rag_queries_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_queries_on_status ON public.rag_queries USING btree (status);


--
-- Name: index_rag_retrieval_results_on_document_chunk_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_retrieval_results_on_document_chunk_id ON public.rag_retrieval_results USING btree (document_chunk_id);


--
-- Name: index_rag_retrieval_results_on_rag_query_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_retrieval_results_on_rag_query_id ON public.rag_retrieval_results USING btree (rag_query_id);


--
-- Name: index_rag_semantic_cache_entries_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_semantic_cache_entries_on_account_id ON public.rag_semantic_cache_entries USING btree (account_id);


--
-- Name: index_rag_semantic_cache_entries_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_semantic_cache_entries_on_expires_at ON public.rag_semantic_cache_entries USING btree (expires_at);


--
-- Name: index_rag_semantic_cache_on_embedding_hnsw; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rag_semantic_cache_on_embedding_hnsw ON public.rag_semantic_cache_entries USING hnsw (question_embedding public.vector_cosine_ops);


--
-- Name: document_chunks document_chunks_search_vector_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER document_chunks_search_vector_trigger BEFORE INSERT OR UPDATE OF content ON public.document_chunks FOR EACH ROW EXECUTE FUNCTION public.document_chunks_search_vector_update();


--
-- Name: rag_feedbacks fk_rails_0d6360f10b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_feedbacks
    ADD CONSTRAINT fk_rails_0d6360f10b FOREIGN KEY (rag_answer_id) REFERENCES public.rag_answers(id);


--
-- Name: rag_answers fk_rails_2daa897efe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_answers
    ADD CONSTRAINT fk_rails_2daa897efe FOREIGN KEY (rag_query_id) REFERENCES public.rag_queries(id);


--
-- Name: rag_retrieval_results fk_rails_371a5bfcc5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_retrieval_results
    ADD CONSTRAINT fk_rails_371a5bfcc5 FOREIGN KEY (rag_query_id) REFERENCES public.rag_queries(id);


--
-- Name: rag_eval_results fk_rails_399d815bac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_eval_results
    ADD CONSTRAINT fk_rails_399d815bac FOREIGN KEY (rag_eval_case_id) REFERENCES public.rag_eval_cases(id);


--
-- Name: rag_semantic_cache_entries fk_rails_90c22d3f68; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_semantic_cache_entries
    ADD CONSTRAINT fk_rails_90c22d3f68 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: document_chunks fk_rails_99b41ada32; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_chunks
    ADD CONSTRAINT fk_rails_99b41ada32 FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: rag_queries fk_rails_a9b8bd7c99; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_queries
    ADD CONSTRAINT fk_rails_a9b8bd7c99 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: rag_retrieval_results fk_rails_d464702a25; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_retrieval_results
    ADD CONSTRAINT fk_rails_d464702a25 FOREIGN KEY (document_chunk_id) REFERENCES public.document_chunks(id) ON DELETE SET NULL;


--
-- Name: rag_eval_results fk_rails_d7859f7ff3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_eval_results
    ADD CONSTRAINT fk_rails_d7859f7ff3 FOREIGN KEY (rag_eval_run_id) REFERENCES public.rag_eval_runs(id);


--
-- Name: document_chunks fk_rails_dc7df17419; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_chunks
    ADD CONSTRAINT fk_rails_dc7df17419 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: documents fk_rails_dd871098c0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT fk_rails_dd871098c0 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: rag_eval_cases fk_rails_f5c7bbc1ff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rag_eval_cases
    ADD CONSTRAINT fk_rails_f5c7bbc1ff FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- PostgreSQL database dump complete
--

\unrestrict lgOOMUBZzhWm5BKYhQpFyNwpmZr54hChEblhuzJhJcyBfOin8RPKKPuVuihgyas

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260728003819'),
('20260728113152'),
('20260728113843'),
('20260728174442'),
('20260729013835'),
('20260730124524'),
('20260730132426'),
('20260730151430'),
('20260731140406'),
('20260731140515'),
('20260731141804'),
('20260731144551'),
('20260731144611'),
('20260731173853'),
('20260803164406'),
('20260803164423');
