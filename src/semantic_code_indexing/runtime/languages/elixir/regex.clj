(ns semantic-code-indexing.runtime.languages.elixir.regex
  (:require [clojure.string :as str]
            [semantic-code-indexing.runtime.languages.elixir.shared :as shared]))

(defn parse-file [path lines]
  (let [line-count (count lines)
        module-name (some (fn [line] (some-> (re-find shared/ex-module-re line) second)) lines)
        alias-map (shared/ex-alias-map lines)
        import-modules (shared/ex-directive-targets lines shared/ex-import-only-re alias-map)
        use-modules (shared/ex-directive-targets lines shared/ex-use-only-re alias-map)
        call-expansion-modules (->> (concat import-modules use-modules)
                                    distinct
                                    vec)
        imports (->> (concat
                      import-modules
                      use-modules
                      (vals alias-map))
                     distinct
                     vec)
        test-target-modules (shared/ex-test-target-modules module-name imports use-modules path)
        defs (->> (map-indexed vector lines)
                  (keep (fn [[idx line]]
                          (cond
                            (re-find shared/ex-test-re line)
                            (let [[_ nm] (re-find shared/ex-test-re line)]
                              {:start-line (inc idx)
                               :form "test"
                               :kind "test"
                               :raw-symbol (shared/ex-test-symbol module-name nm)
                               :signature (shared/trim-signature line)})

                            (re-find shared/ex-def-re line)
                            (let [[_ kw nm] (re-find shared/ex-def-re line)
                                  kind (if (str/includes? path "/test/") "test" "function")]
                              {:start-line (inc idx)
                               :form kw
                               :kind kind
                               :raw-symbol (str (or module-name "Elixir.Unknown") "/" nm)
                               :method_arity (shared/ex-def-arity line)
                               :signature (shared/trim-signature line)}))))
                  vec)
        local-call-arities (->> defs
                                (keep (fn [{:keys [raw-symbol method_arity]}]
                                        (when-let [fn-name (some-> raw-symbol str (str/split #"/" 2) last)]
                                          [fn-name method_arity])))
                                (reduce (fn [acc [fn-name arity]]
                                          (update acc fn-name (fnil conj #{}) arity))
                                        {}))
        ends (->> defs
                  (map-indexed
                   (fn [idx d]
                     (let [start-line (:start-line d)
                           next-start (:start-line (nth defs (inc idx) nil))
                           ceiling-line (max start-line (or (some-> next-start dec) line-count))]
                       (shared/ex-unit-end-line lines start-line ceiling-line (:form d)))))
                  vec)
        unit-records (->> (map vector defs ends)
                          (mapv
                           (fn [[d end-line]]
                             (let [start-line (:start-line d)
                                   body-lines (subvec lines (dec start-line) end-line)
                                   body (str/join "\n" body-lines)
                                   method-arity (:method_arity d)
                                   call-arity-index (if (= "defdelegate" (:form d))
                                                      {}
                                                      (shared/ex-call-arity-index body))]
                               {:unit {:unit_id (cond-> (str path "::" (:raw-symbol d))
                                                  (some? method-arity) (str "$arity" method-arity))
                                       :kind (:kind d)
                                       :symbol (:raw-symbol d)
                                       :path path
                                       :module module-name
                                       :start_line start-line
                                       :end_line end-line
                                       :signature (:signature d)
                                       :summary (str (:form d) " " (:raw-symbol d))
                                       :docstring_excerpt nil
                                       :imports imports
                                       :calls (if (= "defdelegate" (:form d))
                                                (shared/ex-delegate-calls body alias-map)
                                                (shared/extract-ex-calls body module-name alias-map call-expansion-modules local-call-arities call-arity-index))
                                       :method_arity method-arity
                                       :call_arity_by_token (if (= "defdelegate" (:form d))
                                                              {}
                                                              call-arity-index)
                                       :ex_form (:form d)
                                       :parser_mode "full"}
                                :use-expansion-imports
                                (when (and (= "defmacro" (:form d))
                                           (= (str module-name "/__using__") (:raw-symbol d)))
                                  (shared/ex-use-expansion-imports body alias-map))}))))
        units (mapv :unit unit-records)
        use-expansion-imports (->> unit-records
                                   (mapcat #(or (:use-expansion-imports %) []))
                                   distinct
                                   vec)]
    {:language "elixir"
     :module module-name
     :imports imports
     :use_modules use-modules
     :use_expansion_imports use-expansion-imports
     :test_target_modules test-target-modules
     :units units
     :diagnostics []
     :parser_mode "full"}))
