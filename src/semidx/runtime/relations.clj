(ns semidx.runtime.relations
  (:require [clojure.string :as str]))

(def relation-schema-version "v1")

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

(defn- relation-id-input [relation]
  (select-keys relation
               [:source_unit_id
                :target_key
                :target_unit_ids
                :relation_type
                :resolution_status
                :evidence_quality
                :provenance
                :evidence_location
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

(defn valid-relation? [relation]
  (and (map? relation)
       (seq (:relation_id relation))
       (seq (:source_unit_id relation))
       (seq (:relation_type relation))
       (seq (:resolution_status relation))
       (seq (:evidence_quality relation))
       (= relation-schema-version (:relation_schema_version relation))))

(defn normalize-relations [relations]
  (->> relations
       (map normalize-relation)
       (filter valid-relation?)
       (sort-by :relation_id)
       vec))

(def empty-relation-indexes
  {:relations {}
   :relation_forward_index {}
   :relation_reverse_index {}})

(defn index-relations [relations]
  (let [normalized (normalize-relations relations)
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
     :relation_reverse_index reverse-index}))
