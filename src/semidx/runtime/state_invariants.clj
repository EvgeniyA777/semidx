(ns semidx.runtime.state-invariants
  (:require [clojure.string :as str]
            [semidx.runtime.index :as idx]
            [semidx.runtime.query-anchors :as query-anchors]))

(def ^:private output-limit 12)

(defn- unit-reference [unit]
  (select-keys unit [:unit_id :path :symbol]))

(defn- method-name [unit]
  (last (str/split (str (:symbol unit)) #"[#/]")))

(defn- test-unit? [unit]
  (let [path (str (:path unit))]
    (or (= "test" (:kind unit))
        (str/starts-with? path "test/")
        (str/includes? path "/test/")
        (boolean (re-find #"(?:_test|Test)\.[^.]+$" path)))))

(defn- entity-unit? [unit]
  (let [path (str/lower-case (str (:path unit)))
        class-name (str/lower-case (str (:class_name unit)))
        module (str/lower-case (str (:module unit)))]
    (or (boolean (re-find #"(?:^|/)(?:entity|entities|model|models)(?:/|$)" path))
        (str/ends-with? class-name "entity")
        (str/ends-with? class-name "model")
        (str/ends-with? module "entity")
        (str/ends-with? module "model"))))

(defn- writer-unit? [unit]
  (boolean
   (re-find #"(?i)^(?:save|update|disconnect|clear|reset|set)"
            (method-name unit))))

(defn- fixture-helper? [unit entity-class-names]
  (let [candidate-name (method-name unit)
        signature (str/lower-case (str (:signature unit)))]
    (and (boolean (re-find #"(?i)^(?:build|create|make|fixture|sample|given|new)"
                           candidate-name))
         (some #(str/includes? signature %) entity-class-names))))

(defn- distinct-index-units [units]
  (->> units
       (remove nil?)
       (reduce (fn [by-id unit]
                 (assoc by-id (:unit_id unit) unit))
               (sorted-map))
       vals
       vec))

(defn- direct-impact-neighbors [index selected]
  (let [selected-ids (map :unit_id selected)
        neighbor-ids (mapcat (fn [unit-id]
                               (concat (get (:callers_index index) unit-id #{})
                                       (get (:callees_index index) unit-id #{})))
                             selected-ids)
        imported-modules (->> selected
                              (mapcat :imports)
                              (remove nil?)
                              distinct)]
    (distinct-index-units
     (concat selected
             (map #(idx/unit-by-id index %) neighbor-ids)
             (mapcat #(idx/units-for-module index %) imported-modules)))))

(defn- first-reference-per-path [units]
  (second
   (reduce (fn [[seen references] unit]
             (if (contains? seen (:path unit))
               [seen references]
               [(conj seen (:path unit))
                (conj references (unit-reference unit))]))
           [#{} []]
           (sort-by (juxt :path :unit_id) units))))

(defn- assertion-test-paths
  [index all-units selected entity-units related-test-paths]
  (let [interesting-modules (set (keep :module (concat selected entity-units)))
        entity-class-names (->> entity-units
                                (keep :class_name)
                                (map str/lower-case)
                                set)
        target-ids (map :unit_id (concat selected entity-units))
        caller-ids (->> target-ids
                        (mapcat #(get (:callers_index index) % #{}))
                        set)
        linked-test-paths (->> interesting-modules
                               (mapcat #(get (:test_target_index index) % #{}))
                               (remove nil?)
                               distinct
                               sort)
        referencing-test-paths
        (->> all-units
             (filter test-unit?)
             (filter (fn [unit]
                       (let [imports (set (:imports unit))
                             signature (str/lower-case (str (:signature unit)))]
                         (or (contains? caller-ids (:unit_id unit))
                             (some imports interesting-modules)
                             (some #(str/includes? signature %) entity-class-names)))))
             (map :path)
             (remove nil?)
             distinct
             sort)]
    (->> (concat referencing-test-paths
                 linked-test-paths
                 (sort (remove nil? related-test-paths)))
         distinct
         (take output-limit)
         vec)))

(defn assemble
  "Assemble the bounded plans/016 Slice-1 state-invariant packet from existing
   index facts. Returns nil unless the query is stateful and an entity/model
   candidate is found. Field-level facts are deliberately out of scope."
  [index query selected related-test-paths]
  (let [triggered-by (vec (take output-limit
                                (query-anchors/matched-state-terms query)))
        entity-units (when (seq triggered-by)
                       (->> (direct-impact-neighbors index selected)
                            (filter entity-unit?)
                            vec))]
    (when (seq entity-units)
      (let [all-units (idx/all-units index)
            assertion-tests (assertion-test-paths
                             index
                             all-units
                             selected
                             entity-units
                             related-test-paths)
            assertion-test-set (set assertion-tests)
            entity-class-names (->> entity-units
                                    (keep :class_name)
                                    (map str/lower-case)
                                    set)
            fixture-helpers (->> all-units
                                 (filter #(contains? assertion-test-set (:path %)))
                                 (filter #(fixture-helper? % entity-class-names))
                                 (sort-by :unit_id)
                                 (take output-limit)
                                 (mapv unit-reference))
            state-writers (->> selected
                               (filter writer-unit?)
                               (sort-by :unit_id)
                               (take output-limit)
                               (mapv unit-reference))]
        {:packet_version "1.0"
         :triggered_by triggered-by
         :entity_candidates (->> entity-units
                                 first-reference-per-path
                                 (take output-limit)
                                 vec)
         :state_writers state-writers
         :assertion_tests assertion-tests
         :fixture_helpers fixture-helpers
         :guardrail
         {:code "state_invariants_require_whole_file_read"
          :recommendation
          "Read the complete entity/model files, primary service tests, and fixture helpers before editing; field-level write and preservation facts are not available in this packet."}}))))
