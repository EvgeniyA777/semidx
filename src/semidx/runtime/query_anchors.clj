(ns semidx.runtime.query-anchors
  (:require [clojure.string :as str]))

(def ^:private max-anchor-candidates 8)

(defn- distinctv [xs]
  (->> xs
       (remove str/blank?)
       distinct
       vec))

(defn- normalize-symbolish [s]
  (-> (str s)
      str/trim
      str/lower-case
      (str/replace "_" "-")))

(defn- details-text [intent]
  (some-> (:details intent) str str/trim))

(defn qualified-symbol-candidates [details]
  (->> (re-seq #"[A-Za-z][A-Za-z0-9_.-]*/[A-Za-z][A-Za-z0-9_?!*\-]*" (or details ""))
       distinctv
       (take max-anchor-candidates)
       vec))

(defn module-candidates [details]
  (let [qualified-symbols (qualified-symbol-candidates details)
        module-from-symbols (map #(first (str/split % #"/" 2)) qualified-symbols)
        dotted-modules (re-seq #"[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*)+" (or details ""))]
    (->> (concat module-from-symbols dotted-modules)
         distinctv
         (take max-anchor-candidates)
         vec)))

(defn path-candidates [details]
  (->> (re-seq #"(?:src|test|lib|app|scripts|fixtures)/[A-Za-z0-9_./-]+" (or details ""))
       distinctv
       (take max-anchor-candidates)
       vec))

(defn suspected-symbol-candidates [details]
  (let [qualified-symbols (qualified-symbol-candidates details)
        symbolish-tokens (->> (re-seq #"[A-Za-z][A-Za-z0-9_/-]*[_-][A-Za-z0-9_?!*\-]+" (or details ""))
                              (map normalize-symbolish))]
    (->> (concat qualified-symbols symbolish-tokens)
         distinctv
         (take max-anchor-candidates)
         vec)))

(defn infer-anchors [intent]
  (let [details (details-text intent)
        paths (path-candidates details)
        modules (module-candidates details)
        suspected-symbols (suspected-symbol-candidates details)]
    {:targets {}
     :hints (cond-> {}
              (seq paths) (assoc :preferred_paths paths)
              (seq modules) (assoc :preferred_modules modules)
              (seq suspected-symbols) (assoc :suspected_symbols suspected-symbols))}))

(def ^:private state-trigger-terms
  "Bounded set of intent terms that mark a query as state/lifecycle/persistence
   work. Matched by exact (case-normalized) token equality after camelCase and
   snake_case splitting, so `updateStatus` and `connectedAt` tokenize into
   matchable words. Variants are enumerated explicitly for predictable,
   low-noise firing per plans/016."
  #{"disconnect" "disconnects" "disconnected" "disconnecting" "disconnection"
    "reconnect" "reconnects" "reconnected" "reconnecting" "reconnection"
    "connect" "connects" "connected" "connection"
    "status" "statuses"
    "state" "states" "stateful"
    "lifecycle"
    "credential" "credentials"
    "secret" "secrets"
    "token" "tokens"
    "timestamp" "timestamps"
    "persist" "persists" "persisted" "persistence" "persistent"
    "entity" "entities"})

(defn- state-tokens [s]
  (-> (str s)
      (str/replace #"([a-z0-9])([A-Z])" "$1 $2")
      (str/replace #"[^A-Za-z0-9]+" " ")
      str/lower-case
      (str/split #"\s+")
      (->> (remove str/blank?))))

(defn matched-state-terms
  "Return the distinct state-trigger terms present in the query's intent details
   and explicit target symbols. Empty when the query does not read as
   state/lifecycle work. The returned terms double as the diagnostic reason and
   as `:triggered_by` for the state-invariant packet."
  [query]
  (let [details (get-in query [:intent :details])
        symbols (get-in query [:targets :symbols])
        text (str/join " " (cons (str details) (map str symbols)))]
    (->> (state-tokens text)
         (filter state-trigger-terms)
         distinct
         vec)))

(defn state-intent?
  "True when the query concerns state/lifecycle/persistence work, i.e. at least
   one state-trigger term appears in its intent details or target symbols."
  [query]
  (boolean (seq (matched-state-terms query))))
