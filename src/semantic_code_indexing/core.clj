(ns semantic-code-indexing.core
  (:require [semantic-code-indexing.runtime.index :as idx]
            [semantic-code-indexing.runtime.retrieval :as retrieval]
            [semantic-code-indexing.runtime.storage :as storage]))

(defn create-index
  "Create a new in-memory index from a repository root.

  Options:
  - :root_path string (default \".\")
  - :paths vector of relative source paths (optional subset indexing)"
  [opts]
  (idx/create-index opts))

(defn update-index
  "Incrementally update index with changed paths.

  Options:
  - :changed_paths vector of relative source paths"
  [index opts]
  (idx/update-index index opts))

(defn repo-map
  "Return compact repository map from current index." 
  ([index] (idx/repo-map index))
  ([index opts] (idx/repo-map index opts)))

(defn resolve-context
  "Resolve context packet, diagnostics trace and stage events for a retrieval query."
  [index query]
  (retrieval/resolve-context index query))

(defn impact-analysis
  "Return impact hints for the same retrieval query semantics used by resolve-context."
  [index query]
  (retrieval/impact-analysis index query))

(defn skeletons
  "Return skeletons for selected units/paths.

  Selector:
  - :unit_ids vector of unit ids
  - :paths vector of file paths"
  [index selector]
  (retrieval/skeletons index selector))

(defn in-memory-storage
  "Create in-memory storage adapter for index snapshots."
  []
  (storage/in-memory-storage))

(defn postgres-storage
  "Create PostgreSQL storage adapter.

  Options:
  - :db-spec next.jdbc datasource spec map
  - OR :jdbc-url (+ optional :user, :password)"
  [opts]
  (storage/postgres-storage opts))

(defn query-units
  "Query persisted units from storage by root path and optional filters.

  Options:
  - :snapshot_id exact snapshot (optional, latest if omitted)
  - :module exact module name (optional)
  - :symbol exact symbol name (optional)
  - :limit max rows (default 100)"
  [storage-adapter root-path opts]
  (storage/query-units storage-adapter root-path opts))

(defn query-callers
  "Query persisted callers for a unit id."
  [storage-adapter root-path unit-id opts]
  (storage/query-callers storage-adapter root-path unit-id opts))

(defn query-callees
  "Query persisted callees for a unit id."
  [storage-adapter root-path unit-id opts]
  (storage/query-callees storage-adapter root-path unit-id opts))
