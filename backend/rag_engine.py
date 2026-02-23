"""
BarGrader – RAG Engine (multi-backend)

Backends:
  openai_vs  — OpenAI Vector Stores (primary, cloud-based, zero local deps)
  chromadb   — ChromaDB + sentence-transformers (offline / local fallback)

All public methods are **async** so the OpenAI VS backend can make network
calls without blocking the event loop.  ChromaDB calls are fast-local and
simply wrapped in ``async``.

Metadata tagging (subject area, doc type) is shared between backends for
consistent context formatting.
"""
import os
import json
import hashlib
from abc import ABC, abstractmethod
from pathlib import Path
from typing import List, Optional, Dict

from backend.config import settings, BASE_DIR


# ======================================================================
# Shared metadata / tag inference  (used by both backends)
# ======================================================================

_SUBJECT_KEYWORDS: Dict[str, List[str]] = {
    "contracts": ["contract", "offer", "acceptance", "consideration", "ucc", "breach", "parol evidence", "statute of frauds", "promissory estoppel", "mailbox rule"],
    "torts": ["tort", "negligence", "duty", "breach of duty", "causation", "proximate cause", "strict liability", "defamation", "nuisance", "trespass", "battery", "assault", "false imprisonment", "iied", "nied"],
    "constitutional_law": ["constitution", "first amendment", "due process", "equal protection", "commerce clause", "supremacy", "fourteenth amendment", "standing", "strict scrutiny", "rational basis"],
    "criminal_law": ["murder", "manslaughter", "robbery", "burglary", "larceny", "arson", "felony", "misdemeanor", "homicide", "mens rea", "actus reus", "self-defense", "insanity defense", "model penal code"],
    "criminal_procedure": ["fourth amendment", "search and seizure", "miranda", "exclusionary rule", "probable cause", "warrant", "fifth amendment", "sixth amendment", "right to counsel"],
    "evidence": ["hearsay", "relevance", "character evidence", "privilege", "authentication", "best evidence", "expert witness", "impeachment", "fre ", "federal rules of evidence"],
    "civil_procedure": ["jurisdiction", "venue", "personal jurisdiction", "subject matter jurisdiction", "diversity", "federal question", "res judicata", "collateral estoppel"],
    "real_property": ["real property", "easement", "covenant", "deed", "mortgage", "adverse possession", "landlord", "tenant", "future interest", "fee simple", "life estate", "joint tenancy", "tenancy in common"],
    "community_property": ["community property", "separate property", "quasi-community", "transmutation", "commingling", "putative spouse"],
    "professional_responsibility": ["ethical", "conflict of interest", "attorney-client", "fiduciary", "malpractice", "competence", "diligence", "confidentiality"],
    "wills_trusts": ["will", "trust", "intestate", "probate", "testamentary", "revocable", "irrevocable", "beneficiary", "executor", "trustee"],
    "remedies": ["damages", "injunction", "specific performance", "restitution", "compensatory", "punitive damages", "equitable"],
}

_DOC_TYPE_PATTERNS = {
    "outline": ["outline", "summary", "overview", "review", "cheat sheet"],
    "model_answer": ["model answer", "sample answer", "essay answer", "example answer"],
    "statute": ["statute", "code section", "§", "penal code", "civil code", "evidence code"],
    "case_brief": ["case brief", "holding", "procedural history", "facts of the case"],
    "rule_statement": ["rule statement", "black letter law", "elements"],
    "practice_question": ["practice question", "hypo", "hypothetical", "essay prompt", "call of the question"],
    "study_guide": ["study guide", "bar prep", "mnemonics", "checklist"],
}


def _detect_subjects(text: str) -> List[str]:
    text_lower = text.lower()
    found = []
    for subject, keywords in _SUBJECT_KEYWORDS.items():
        score = sum(1 for kw in keywords if kw in text_lower)
        if score >= 2:
            found.append(subject)
    return found or ["general"]


def _detect_doc_type(text: str, filename: str = "") -> str:
    combined = (text[:2000] + " " + filename).lower()
    for dtype, patterns in _DOC_TYPE_PATTERNS.items():
        if any(p in combined for p in patterns):
            return dtype
    return "reference"


def _load_sidecar_metadata(path: Path) -> Dict:
    sidecar = path.with_suffix(path.suffix + ".meta.json")
    if not sidecar.exists():
        sidecar = path.with_name(path.stem + ".meta.json")
    if sidecar.exists():
        try:
            return json.loads(sidecar.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"[RAG] Sidecar load error {sidecar}: {e}")
    return {}


# ======================================================================
# Chunking / doc-loading helpers  (used by ChromaDB backend)
# ======================================================================

def _chunk_text(text: str, size: int = None, overlap: int = None) -> List[str]:
    size = size or settings.chunk_size
    overlap = overlap or settings.chunk_overlap
    chunks, start = [], 0
    while start < len(text):
        chunks.append(text[start : start + size])
        start += size - overlap
    return [c.strip() for c in chunks if c.strip()]


def _hash_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def load_document(path: Path) -> str:
    ext = path.suffix.lower()
    if ext == ".pdf":
        try:
            from PyPDF2 import PdfReader
            return "\n".join(p.extract_text() or "" for p in PdfReader(str(path)).pages)
        except Exception as e:
            print(f"[RAG] PDF error {path}: {e}")
            return ""
    elif ext in (".docx", ".doc"):
        try:
            import docx2txt
            return docx2txt.process(str(path))
        except Exception as e:
            print(f"[RAG] DOCX error {path}: {e}")
            return ""
    else:
        return path.read_text(encoding="utf-8", errors="ignore")


def _format_hits(hits: List[dict]) -> str:
    """Shared formatting for context blocks."""
    if not hits:
        return ""
    parts = []
    for i, h in enumerate(hits, 1):
        header = f"[Source {i}: {h['source']}"
        if h.get("subject"):
            header += f" | {h['subject']}"
        if h.get("doc_type"):
            header += f" | {h['doc_type']}"
        header += "]"
        parts.append(f"{header}\n{h['text']}")
    return "\n\n---\n\n".join(parts)


# ======================================================================
# Abstract base
# ======================================================================

class BaseRAGEngine(ABC):
    """Common interface for all RAG backends."""

    @abstractmethod
    async def query(self, question: str, top_k: int = None,
                    subject_filter: str = None, *, mode: str = "essay") -> List[dict]:
        ...

    async def get_context_block(self, question: str, top_k: int = None,
                                subject_filter: str = None, mode: str = "essay") -> str:
        """Retrieve RAG context, ordered by mode.

        Mode controls which vector stores are searched and in what order:
          essay   → Exemplary → Attack → Source  (full depth)
          outline → Exemplary → Attack           (skip Source for speed)
          mbe     → Source only                   (bar materials compendium)
        """
        hits = await self.query(question, top_k, subject_filter, mode=mode)
        return _format_hits(hits)

    @abstractmethod
    async def doc_count(self) -> int:
        ...

    # Ingestion — only meaningful for ChromaDB; no-ops for cloud stores.
    async def ingest_directory(self, dir_path: str = None) -> int:
        return 0

    async def ingest_file(self, path: Path) -> int:
        return 0

    async def ingest_text(self, text: str, source: str = "manual", subject: str = "", doc_type: str = "") -> int:
        return 0


# ======================================================================
# Backend 1: OpenAI Vector Stores
# ======================================================================

class OpenAIVSEngine(BaseRAGEngine):
    """RAG powered by OpenAI Vector Stores (cloud).

    Searches the vector stores listed in ``settings.openai_vs_store_map``.
    Ingestion is managed externally via the OpenAI dashboard / API.
    """

    def __init__(self):
        self._client = None

    @property
    def client(self):
        if self._client is None:
            from openai import AsyncOpenAI
            self._client = AsyncOpenAI(api_key=settings.openai_api_key)
        return self._client

    async def query(self, question: str, top_k: int = None,
                    subject_filter: str = None, *, mode: str = "essay") -> List[dict]:
        """Search vector stores in pipeline order determined by *mode*.

        Pipeline ordering (maintained in returned results):
          essay   → Exemplary → Attack → Source  (full depth)
          outline → Exemplary → Attack           (skip Source)
          mbe     → Source only                   (concise bar materials)

        Within each stage results are sorted by relevance; stages are
        concatenated so exemplary content appears first, then attack
        outlines, then source material.  Duplicate VS IDs (e.g. when
        Exemplary and Attack share a store) are searched only once.
        """
        top_k = top_k or settings.top_k_results
        stages = settings.stores_for_mode(mode)
        if not stages:
            # Fallback: try the flat store map
            store_map = settings.openai_vs_store_map
            if not store_map:
                return []
            stages = list(store_map.items())

        # Distribute top_k across stages (at least 3 per stage)
        per_stage = max(3, top_k // max(len(stages), 1))

        all_hits: List[dict] = []
        seen_vs_ids: set = set()          # skip duplicate VS IDs

        for label, vs_id in stages:
            if vs_id in seen_vs_ids:
                continue
            seen_vs_ids.add(vs_id)

            try:
                results = await self.client.vector_stores.search(
                    vector_store_id=vs_id,
                    query=question,
                    max_num_results=per_stage,
                )
                stage_hits: List[dict] = []
                for item in results.data:
                    text_parts = []
                    if hasattr(item, "content") and item.content:
                        for c in item.content:
                            if hasattr(c, "text"):
                                text_parts.append(c.text)
                    text = " ".join(text_parts)
                    if not text.strip():
                        continue
                    stage_hits.append({
                        "id":       getattr(item, "file_id", ""),
                        "text":     text,
                        "source":   getattr(item, "filename", label),
                        "subject":  ",".join(_detect_subjects(text)),
                        "doc_type": label,
                        "distance": 1.0 - getattr(item, "score", 0.0),
                    })
                # Sort within stage by relevance (lowest distance first)
                stage_hits.sort(key=lambda h: h["distance"])
                all_hits.extend(stage_hits)
            except Exception as e:
                print(f"[RAG] OpenAI VS search error ({label} / {vs_id}): {e}")

        return all_hits[:top_k]

    async def doc_count(self) -> int:
        store_map = settings.openai_vs_store_map
        if not store_map:
            return 0
        total, seen = 0, set()
        for label, vs_id in store_map.items():
            if vs_id in seen:
                continue
            seen.add(vs_id)
            try:
                vs = await self.client.vector_stores.retrieve(vs_id)
                total += vs.file_counts.completed
            except Exception as e:
                print(f"[RAG] VS count error ({label}): {e}")
        return total


# ======================================================================
# Backend 2: ChromaDB (offline / local)
# ======================================================================

class ChromaRAGEngine(BaseRAGEngine):
    """RAG powered by ChromaDB + sentence-transformers (fully local)."""

    COLLECTION_NAME = "bar_exam_docs"

    def __init__(self):
        import chromadb
        persist_dir = settings.chroma_persist_dir
        os.makedirs(persist_dir, exist_ok=True)
        self._chroma = chromadb.PersistentClient(path=persist_dir)
        self.collection = self._chroma.get_or_create_collection(
            name=self.COLLECTION_NAME,
            metadata={"hnsw:space": "cosine"},
        )
        self._embedder = None

    @property
    def embedder(self):
        if self._embedder is None:
            from sentence_transformers import SentenceTransformer
            self._embedder = SentenceTransformer(settings.embedding_model)
        return self._embedder

    # -- Ingestion ------------------------------------------------------

    async def ingest_directory(self, dir_path: str = None) -> int:
        dir_path = Path(dir_path or (BASE_DIR / "data" / "bar_exam_docs"))
        if not dir_path.exists():
            print(f"[RAG] Directory not found: {dir_path}")
            return 0
        total = 0
        for fpath in sorted(dir_path.rglob("*")):
            if fpath.is_file() and fpath.suffix.lower() in (
                ".txt", ".md", ".pdf", ".docx", ".doc", ".rst",
            ):
                added = await self.ingest_file(fpath)
                total += added
        print(f"[RAG] Ingested {total} chunks from {dir_path}")
        return total

    async def ingest_file(self, path: Path) -> int:
        text = load_document(path)
        if not text.strip():
            return 0
        sidecar = _load_sidecar_metadata(path)
        subjects = sidecar.get("subject") or _detect_subjects(text)
        doc_type = sidecar.get("doc_type") or _detect_doc_type(text, path.name)
        topics = sidecar.get("topics", [])

        chunks = _chunk_text(text)
        ids, docs, metas = [], [], []
        for i, chunk in enumerate(chunks):
            cid = f"{path.stem}_{_hash_text(chunk)}_{i}"
            ids.append(cid)
            docs.append(chunk)
            chunk_subjects = _detect_subjects(chunk) if len(subjects) > 1 else subjects
            metas.append({
                "source": str(path.name),
                "chunk_index": i,
                "subject": ",".join(chunk_subjects),
                "doc_type": doc_type,
                "topics": ",".join(topics) if topics else "",
            })

        embeddings = self.embedder.encode(docs).tolist()
        self.collection.upsert(ids=ids, documents=docs, embeddings=embeddings, metadatas=metas)
        print(f"[RAG] Ingested {path.name}: {len(ids)} chunks | subjects={subjects} type={doc_type}")
        return len(ids)

    async def ingest_text(self, text: str, source: str = "manual", subject: str = "", doc_type: str = "") -> int:
        chunks = _chunk_text(text)
        subjects = subject if subject else ",".join(_detect_subjects(text))
        dtype = doc_type if doc_type else _detect_doc_type(text, source)
        ids, docs, metas = [], [], []
        for i, chunk in enumerate(chunks):
            ids.append(f"{source}_{_hash_text(chunk)}_{i}")
            docs.append(chunk)
            metas.append({"source": source, "chunk_index": i, "subject": subjects, "doc_type": dtype, "topics": ""})
        embeddings = self.embedder.encode(docs).tolist()
        self.collection.upsert(ids=ids, documents=docs, embeddings=embeddings, metadatas=metas)
        return len(ids)

    # -- Retrieval ------------------------------------------------------

    async def query(self, question: str, top_k: int = None,
                    subject_filter: str = None, *, mode: str = "essay") -> List[dict]:
        top_k = top_k or settings.top_k_results
        if self.collection.count() == 0:
            return []
        q_emb = self.embedder.encode([question]).tolist()
        where_filter = {"subject": {"$contains": subject_filter}} if subject_filter else None

        results = self.collection.query(
            query_embeddings=q_emb,
            n_results=min(top_k, self.collection.count()),
            include=["documents", "metadatas", "distances"],
            where=where_filter,
        )
        hits = []
        for i in range(len(results["ids"][0])):
            meta = results["metadatas"][0][i]
            hits.append({
                "id": results["ids"][0][i],
                "text": results["documents"][0][i],
                "source": meta.get("source", ""),
                "subject": meta.get("subject", ""),
                "doc_type": meta.get("doc_type", ""),
                "distance": results["distances"][0][i],
            })
        return hits

    async def doc_count(self) -> int:
        return self.collection.count()


# ======================================================================
# Factory + singleton
# ======================================================================

def _create_engine() -> BaseRAGEngine:
    backend = settings.rag_backend.lower()

    if backend == "openai_vs":
        store_map = settings.openai_vs_store_map
        if store_map and settings.openai_api_key:
            print(f"[RAG] Using OpenAI Vector Stores ({len(store_map)} stores configured)")
            return OpenAIVSEngine()
        print("[RAG] OpenAI VS requested but no stores / API key configured — falling back to ChromaDB")

    try:
        engine = ChromaRAGEngine()
        print("[RAG] Using ChromaDB (local)")
        return engine
    except ImportError:
        print("[RAG] ChromaDB not installed — returning no-op engine")
        return _NoopRAGEngine()
    except Exception as exc:
        print(f"[RAG] ChromaDB init failed ({exc.__class__.__name__}: {exc}) — returning no-op engine")
        return _NoopRAGEngine()


class _NoopRAGEngine(BaseRAGEngine):
    """Placeholder when no RAG backend is available."""

    async def query(self, question: str, top_k: int = None,
                    subject_filter: str = None, *, mode: str = "essay") -> List[dict]:
        return []

    async def doc_count(self) -> int:
        return 0


rag_engine: BaseRAGEngine = _create_engine()
