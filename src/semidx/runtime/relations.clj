(ns semidx.runtime.relations
  (:require [clojure.string :as str]))

(def relation-schema-version "v1")

(def relation-types
  "Known v1 typed-relation kinds. New relation kinds must be added here before
  producers emit them; unknown kinds are rejected with a structured diagnostic."
  #{"dataflow/local-binding-call-result"
    "dataflow/returns-call-result"
    "dataflow/passes-argument"})

(def resolution-statuses
  "Valid resolution states for a typed relation."
  #{"resolved" "ambiguous" "unresolved"})

(def evidence-qualities
  "Valid evidence-quality grades for a typed relation."
  #{"high" "medium" "low" "unknown"})

(defn- blank->nil [value]
  (let [s (some-> value str str/trim)]
    (when-not (str/blank? s) s)))

(defn- distinct-strings [values]
  (->> values
       (keep blank->nil)
       distinct
       vec))

(defn- sha1 [value]
  (let [digest (.digest (java.security.MessageDigest/getInstance "SHA-1")
                        (.getBytes (str value) "UTF-8"))]
    (apply str (map #(format "%02x" (bit-and 0xff %)) digest))))

(defn- canonical-value [value]
  (cond
    (map? value)
    (into (sorted-map-by (fn [a b] (compare (pr-str a) (pr-str b))))
          (map (fn [[k v]] [k (canonical-value v)]) value))

    (sequential? value)
    (mapv canonical-value value)

    (set? value)
    (->> value (map canonical-value) (sort-by pr-str) vec)

    :else value))

(defn- relation-id-input
  "Stable semantic identity of a relation. Identity derives only from the
  relation type, source endpoint, semantic target key, and flow payload
  (`:local_name` / `:arg_index`), scoped by the relation schema version.

  Mutable resolution and evidence fields (`:target_unit_ids`,
  `:resolution_status`, `:evidence_quality`, `:provenance`,
  `:evidence_location`) are intentionally excluded so that resolving an
  unresolved fact or attaching richer evidence enriches one semantic edge
  instead of minting a second one. See ADR-039."
  [relation]
  (select-keys relation
               [:relation_type
                :source_unit_id
                :target_key
                :local_name
                :arg_index
                :relation_schema_version]))

(defn relation-id [relation]
  (str "rel:" (sha1 (pr-str (canonical-value (relation-id-input relation))))))

(defn normalize-relation [relation]
  (let [target-unit-ids (distinct-strings (:target_unit_ids relation))
        normalized (cond-> (assoc relation
                                  :source_unit_id (blank->nil (:source_unit_id relation))
                                  :target_key (blank->nil (:target_key relation))
                                  :target_unit_ids target-unit-ids
                                  :relation_type (blank->nil (:relation_type relation))
                                  :resolution_status (or (blank->nil (:resolution_status relation))
                                                         (if (seq target-unit-ids) "resolved" "unresolved"))
                                  :evidence_quality (or (blank->nil (:evidence_quality relation))
                                                        "unknown")
                                  :provenance (or (:provenance relation) {})
                                  :relation_schema_version relation-schema-version)
                     (contains? relation :evidence_location)
                     (assoc :evidence_location (:evidence_location relation)))]
    (assoc normalized :relation_id (or (blank->nil (:relation_id relation))
                                       (relation-id normalized)))))

(defn relation-errors
  "Validate a normalized relation against the explicit internal schema and
  return a vector of structured error maps ({:code :field :message}). An empty
  vector means the relation is valid. Invalid facts are surfaced as diagnostics
  rather than silently dropped."
  [relation]
  (if-not (map? relation)
    [{:code :not-a-map :field nil :message "Relation must be a map."}]
    (let [{:keys [relation_id source_unit_id relation_type resolution_status
                  evidence_quality relation_schema_version target_unit_ids
                  evidence_location provenance]} relation]
      (cond-> []
        (not (seq relation_id))
        (conj {:code :missing-relation-id :field :relation_id
               :message "Relation is missing relation_id."})

        (not (seq source_unit_id))
        (conj {:code :missing-source-unit-id :field :source_unit_id
               :message "Relation is missing source_unit_id."})

        (not (contains? relation-types relation_type))
        (conj {:code :invalid-relation-type :field :relation_type
               :message (str "Unknown relation_type: " (pr-str relation_type) ".")})

        (not (contains? resolution-statuses resolution_status))
        (conj {:code :invalid-resolution-status :field :resolution_status
               :message (str "Unknown resolution_status: " (pr-str resolution_status) ".")})

        (not (contains? evidence-qualities evidence_quality))
        (conj {:code :invalid-evidence-quality :field :evidence_quality
               :message (str "Unknown evidence_quality: " (pr-str evidence_quality) ".")})

        (not= relation-schema-version relation_schema_version)
        (conj {:code :schema-version-mismatch :field :relation_schema_version
               :message (str "Expected relation_schema_version "
                             (pr-str relation-schema-version) ".")})

        (and (= "resolved" resolution_status) (not (seq target_unit_ids)))
        (conj {:code :resolved-without-targets :field :target_unit_ids
               :message "Resolved relation must have at least one target unit id."})

        (and (some? evidence_location) (not (map? evidence_location)))
        (conj {:code :invalid-evidence-location :field :evidence_location
               :message "evidence_location must be a map when present."})

        (and (some? provenance) (not (map? provenance)))
        (conj {:code :invalid-provenance :field :provenance
               :message "provenance must be a map when present."})))))

(defn valid-relation?
  "True when a normalized relation satisfies the explicit internal schema."
  [relation]
  (empty? (relation-errors relation)))

(defn- relation-diagnostic [relation]
  {:relation_id (:relation_id relation)
   :source_unit_id (:source_unit_id relation)
   :relation_type (:relation_type relation)
   :errors (relation-errors relation)})

(defn normalize-relations-with-diagnostics
  "Normalize a collection of relations and partition them into valid facts and
  structured diagnostics for invalid facts. Returns
  {:relations <sorted valid vec> :diagnostics <vec of {:relation_id
  :source_unit_id :relation_type :errors}>}. Invalid facts are excluded from
  :relations but surfaced in :diagnostics rather than dropped silently."
  [relations]
  (let [normalized (map normalize-relation relations)
        {valid true invalid false} (group-by (comp empty? relation-errors) normalized)]
    {:relations (->> valid (sort-by :relation_id) vec)
     :diagnostics (mapv relation-diagnostic invalid)}))

(defn normalize-relations [relations]
  (:relations (normalize-relations-with-diagnostics relations)))

(def empty-relation-indexes
  {:relations {}
   :relation_forward_index {}
   :relation_reverse_index {}
   :relation_diagnostics []})

(defn index-relations [relations]
  (let [{normalized :relations diagnostics :diagnostics}
        (normalize-relations-with-diagnostics relations)
        relations-by-id (into {} (map (juxt :relation_id identity) normalized))
        forward-index (reduce (fn [acc {:keys [relation_id source_unit_id]}]
                                (update acc source_unit_id (fnil conj #{}) relation_id))
                              {}
                              normalized)
        reverse-index (reduce (fn [acc {:keys [relation_id target_key target_unit_ids]}]
                                (reduce (fn [a target]
                                          (update a target (fnil conj #{}) relation_id))
                                        acc
                                        (concat target_unit_ids
                                                (when (seq target_key)
                                                  [target_key]))))
                              {}
                              normalized)]
    {:relations relations-by-id
     :relation_forward_index forward-index
     :relation_reverse_index reverse-index
     :relation_diagnostics diagnostics}))
