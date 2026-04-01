(ns semidx.runtime.languages.elixir.shared
  (:require [clojure.string :as str]))

(def ex-module-re #"^\s*defmodule\s+([A-Za-z0-9_\.]+)\s+do")
(def ex-import-only-re #"^\s*import\s+([A-Za-z0-9_\.]+)")
(def ex-use-only-re #"^\s*use\s+([A-Za-z0-9_\.]+)")
(def ex-alias-line-re #"^\s*alias\s+(.+)$")
(def ex-def-re #"^\s*(defdelegate|defp?|defmacro|defmacrop)\s+([a-zA-Z_][a-zA-Z0-9_!?]*)")
(def ex-test-re #"^\s*test\s+\"([^\"]+)\"\s+do")
(def ex-call-re #"\b([A-Za-z_][A-Za-z0-9_\.!?]*)\s*\(")
(def ex-call-with-args-re #"\b([A-Za-z_][A-Za-z0-9_\.!?]*)\s*\(([^)]*)\)")
(def ex-capture-re #"&([A-Za-z_][A-Za-z0-9_\.!?]*)/([0-9]+)")
(def ex-pipeline-call-re #"\|>\s*([A-Za-z_][A-Za-z0-9_\.!?]*)\s*\(([^)]*)\)")

(def ex-call-stop
  #{"if" "case" "cond" "with" "fn" "def" "defp" "defmacro" "defdelegate" "defmodule" "test" "describe" "quote" "unquote" "alias" "import" "require" "use"})

(def ex-test-module-suffixes
  ["Test"])

(defn trim-signature [line]
  (let [t (str/trim (or line ""))]
    (subs t 0 (min 180 (count t)))))

(defn tail-token [token]
  (some-> token str (str/split #"[\./#]") last))

(defn ex-test-symbol [module test-name]
  (let [slug (-> test-name
                 str/lower-case
                 (str/replace #"[^a-z0-9]+" "-")
                 (str/replace #"^-+|-+$" ""))]
    (str (or module "Elixir.Unknown") "/test-" (if (seq slug) slug "unnamed"))))

(defn ex-last-segment [module]
  (some-> module str (str/split #"\.") last))

(defn ex-strip-test-suffix [module]
  (reduce (fn [acc suffix]
            (if (str/ends-with? acc suffix)
              (subs acc 0 (- (count acc) (count suffix)))
              acc))
          (str module)
          ex-test-module-suffixes))

(defn ex-strip-comment [line]
  (first (str/split (str line) #"#" 2)))

(defn ex-rewrite-alias-prefix [token alias-map]
  (let [parts (->> (str/split (str token) #"\.")
                   (remove str/blank?)
                   vec)
        n (count parts)]
    (loop [i n]
      (when (pos? i)
        (let [prefix (str/join "." (take i parts))]
          (if-let [mapped (get alias-map prefix)]
            (let [suffix (drop i parts)]
              (if (seq suffix)
                (str mapped "." (str/join "." suffix))
                mapped))
            (recur (dec i))))))))

(defn ex-resolve-alias-ref [token alias-map]
  (loop [current (str token)
         step 0]
    (if (>= step 8)
      current
      (if-let [rewritten (ex-rewrite-alias-prefix current alias-map)]
        (if (= rewritten current)
          current
          (recur rewritten (inc step)))
        current))))

(defn ex-expand-alias-targets [target-expr alias-map]
  (let [target* (-> target-expr ex-strip-comment str/trim)]
    (if-let [[_ base inner] (re-find #"^([A-Za-z0-9_\.]+)\.\{([^}]+)\}$" target*)]
      (let [base* (ex-resolve-alias-ref base alias-map)]
        (->> (str/split inner #",")
             (map str/trim)
             (remove str/blank?)
             (map (fn [tail]
                    (ex-resolve-alias-ref (str base* "." tail) alias-map)))
             vec))
      [(ex-resolve-alias-ref target* alias-map)])))

(defn ex-alias-entries-for-line [line alias-map]
  (when-let [[_ body] (re-find ex-alias-line-re line)]
    (let [body* (-> body ex-strip-comment str/trim)
          [_ target-expr explicit-as] (or (re-find #"^(.*?),\s*as:\s*([A-Za-z0-9_\.]+)\s*$" body*)
                                          [nil body* nil])
          targets (ex-expand-alias-targets target-expr alias-map)]
      (->> targets
           (map-indexed
            (fn [idx full]
              (let [alias (if (and (seq explicit-as) (= 1 (count targets)) (zero? idx))
                            explicit-as
                            (ex-last-segment full))]
                (when (and (seq alias) (seq full))
                  [alias full]))))
           (remove nil?)
           vec))))

(defn ex-alias-map [lines]
  (reduce
   (fn [acc line]
     (reduce (fn [m [alias full]] (assoc m alias full))
             acc
             (or (ex-alias-entries-for-line line acc) [])))
   {}
   lines))

(defn ex-directive-targets [lines directive-re alias-map]
  (->> lines
       (keep (fn [line]
               (some-> (re-find directive-re line)
                       second
                       ex-strip-comment
                       (str/split #"," 2)
                       first
                       str/trim
                       (ex-resolve-alias-ref alias-map))))
       (remove str/blank?)
       distinct
       vec))

(defn ex-keyword-count [line kw]
  (count (re-seq (re-pattern (str "\\b" kw "\\b")) (str line))))

(defn ex-unit-end-line [lines start-line ceiling-line form]
  (if (= form "defdelegate")
    start-line
    (let [start-idx (max 0 (dec start-line))
          end-idx (max start-idx (dec ceiling-line))]
      (loop [idx start-idx
             depth 0
             saw-do false]
        (if (> idx end-idx)
          (inc end-idx)
          (let [line (nth lines idx "")
                do-count (ex-keyword-count line "do")
                end-count (ex-keyword-count line "end")
                depth* (- (+ depth do-count) end-count)
                saw-do* (or saw-do (pos? do-count))
                complete? (and saw-do* (<= depth* 0))]
            (if complete?
              (inc idx)
              (recur (inc idx) depth* saw-do*))))))))

(defn ex-expand-alias-token [token alias-map]
  (let [expanded (ex-resolve-alias-ref token alias-map)]
    (when (not= (str token) expanded)
      expanded)))

(defn ex-expand-module-self-token [token module-name]
  (let [token* (str token)]
    (if-let [[_ suffix] (re-matches #"__MODULE__\.(.+)" token*)]
      (when (seq module-name)
        [(str module-name "." suffix)
         (str module-name "/" suffix)])
      [])))

(defn ex-local-call-shadowed? [token arities local-call-arities]
  (let [local-arities (get local-call-arities (str token))]
    (cond
      (empty? local-arities) false
      (seq arities) (boolean (some #(contains? local-arities %) arities))
      :else true)))

(defn ex-expand-import-token [token import-modules local-call-arities call-arity-index]
  (let [arities (or (get call-arity-index (str token))
                    (get call-arity-index (tail-token token))
                    #{})]
    (when-not (or (str/includes? (str token) ".")
                  (ex-local-call-shadowed? token arities local-call-arities))
      (->> import-modules
           (mapcat (fn [module]
                     [(str module "." token)
                      (str module "/" token)]))
           distinct
           vec))))

(defn ex-args-arity [args-text]
  (let [s (str/trim (or args-text ""))]
    (if (str/blank? s)
      0
      (loop [chars (seq s)
             depth 0
             in-string? false
             escaped? false
             arity 1]
        (if-let [ch (first chars)]
          (cond
            escaped?
            (recur (next chars) depth in-string? false arity)

            in-string?
            (cond
              (= ch \\) (recur (next chars) depth in-string? true arity)
              (= ch \") (recur (next chars) depth false false arity)
              :else (recur (next chars) depth in-string? false arity))

            (= ch \")
            (recur (next chars) depth true false arity)

            (#{\( \[ \{} ch)
            (recur (next chars) (inc depth) in-string? false arity)

            (#{\) \] \}} ch)
            (recur (next chars) (max 0 (dec depth)) in-string? false arity)

            (and (= ch \,) (zero? depth))
            (recur (next chars) depth in-string? false (inc arity))

            :else
            (recur (next chars) depth in-string? false arity))
          arity)))))

(defn ex-def-arity [line]
  (when-let [[_ _ _ args] (re-find #"^\s*(defdelegate|defp?|defmacro|defmacrop)\s+([a-zA-Z_][a-zA-Z0-9_!?]*)\s*(?:\(([^)]*)\))?" line)]
    (when (some? args)
      (ex-args-arity args))))

(defn ex-call-arity-index [body]
  (reduce (fn [acc {:keys [token arity]}]
            (let [tail (tail-token token)]
              (cond-> acc
                (seq token) (update token (fnil conj #{}) arity)
                (and tail (not= tail token)) (update tail (fnil conj #{}) arity))))
          {}
          (concat
           (map (fn [[_ token args]]
                  {:token token
                   :arity (ex-args-arity args)})
                (re-seq ex-call-with-args-re body))
           (map (fn [[_ token arity]]
                  {:token token
                   :arity (Long/parseLong arity)})
                (re-seq ex-capture-re body))
           (map (fn [[_ token args]]
                  {:token token
                   :arity (inc (ex-args-arity args))})
                (re-seq ex-pipeline-call-re body)))))

(defn ex-delegate-calls [body alias-map]
  (if-let [[_ fun target] (re-find #"defdelegate\s+([a-zA-Z_][a-zA-Z0-9_!?]*)\s*(?:\([^)]*\))?\s*,\s*to:\s*([A-Za-z0-9_\.]+)" body)]
    (let [target* (ex-resolve-alias-ref target alias-map)]
      (->> [(str target* "." fun)
            (str target* "/" fun)]
           (remove str/blank?)
           distinct
           vec))
    []))

(defn ex-use-expansion-imports [body alias-map]
  (->> (str/split-lines (str body))
       (mapcat #(or (ex-directive-targets [%] ex-import-only-re alias-map) []))
       distinct
       vec))

(defn ex-capture-tokens [body]
  (->> (re-seq ex-capture-re body)
       (map second)
       distinct
       vec))

(defn extract-ex-calls [body module-name alias-map import-modules local-call-arities call-arity-index]
  (->> (concat (map second (re-seq ex-call-re body))
               (ex-capture-tokens body))
       (mapcat (fn [token]
                 (let [expanded (ex-expand-alias-token token alias-map)
                       module-self (ex-expand-module-self-token token module-name)
                       imported (ex-expand-import-token token import-modules local-call-arities call-arity-index)]
                   (cond-> [token]
                     (seq expanded) (conj expanded)
                     (seq module-self) (into module-self)
                     (seq imported) (into imported)))))
       (mapcat (fn [token]
                 (let [tail (tail-token token)]
                   (cond-> [token]
                     (and tail (not= tail token)) (conj tail)))))
       (remove #(contains? ex-call-stop %))
       distinct
       vec))

(defn ex-test-target-modules [module imports uses path]
  (let [module* (str (or module ""))
        exunit-test? (some #{"ExUnit.Case"} uses)]
    (if (or (str/includes? (str path) "/test/")
            (str/ends-with? module* "Test")
            exunit-test?)
      (->> (concat [(ex-strip-test-suffix module*)] imports)
           (remove #(or (str/blank? %)
                        (= % "ExUnit.Case")))
           distinct
           vec)
      [])))
