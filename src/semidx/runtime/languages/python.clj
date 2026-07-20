(ns semidx.runtime.languages.python
  (:require [clojure.string :as str]
            [semidx.runtime.languages.shared :as shared]))

(def ^:private py-import-re #"^\s*import\s+([a-zA-Z0-9_\.]+)(?:\s+as\s+([A-Za-z0-9_]+))?")
(def ^:private py-from-import-re #"^\s*from\s+([a-zA-Z0-9_\.]+)\s+import\s+([A-Za-z0-9_,\s\*_]+)")
(def ^:private py-class-re #"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)")
(def ^:private py-def-re #"^\s*(?:async\s+def|def)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
(def ^:private py-call-re #"\b([A-Za-z_][A-Za-z0-9_\.]*)\s*\(")

(def ^:private py-call-stop
  #{"if" "for" "while" "return" "yield" "lambda" "class" "def" "print"})

(defn- trim-signature [line]
  (shared/trim-signature line))

(defn- unit-end-lines [starts total-lines]
  (shared/unit-end-lines starts total-lines))

(defn- tail-token [token]
  (shared/tail-token token))

(defn- py-module-name [path]
  (-> path
      (str/replace #"\.py$" "")
      (str/replace #"/" ".")
      (str/replace #"^\.+" "")))

(defn- py-normalize-relative-module [module import-module]
  (let [import* (str import-module)]
    (if (str/starts-with? import* ".")
      (let [dot-count (count (re-find #"^\.*" import*))
            suffix (str/replace import* #"^\.*" "")
            module-parts (->> (str/split (str module) #"\.")
                              (remove str/blank?))
            package-parts (vec (butlast module-parts))
            up-levels (max 0 (dec dot-count))
            kept-count (max 0 (- (count package-parts) up-levels))
            base-parts (subvec package-parts 0 kept-count)
            suffix-parts (->> (str/split suffix #"\.")
                              (remove str/blank?))
            resolved (concat base-parts suffix-parts)]
        (str/join "." resolved))
      import*)))

(defn- py-test-path? [path]
  (let [p (str/lower-case (str path))]
    (or (str/includes? p "/test/")
        (str/includes? p "/tests/")
        (str/ends-with? p "_test.py")
        (str/starts-with? (last (str/split p #"/")) "test_"))))

(defn- py-strip-test-module [module]
  (let [m (str module)]
    (cond
      (str/ends-with? m "_test") (subs m 0 (- (count m) 5))
      (re-find #"\.test_[^.]+$" m) (str/replace m #"\.test_[^.]+$" "")
      :else m)))

(defn- py-kind [path fn-name]
  (if (or (py-test-path? path)
          (str/starts-with? fn-name "test_")
          (str/starts-with? (str/lower-case (or fn-name "")) "test"))
    "test"
    "function"))

(defn- py-indent [line]
  (count (re-find #"^\s*" line)))

(defn- py-in-class-context [stack indent]
  (->> stack
       (filter #(< (:indent %) indent))
       last
       :name))

(defn- py-import-state [module lines]
  (reduce
   (fn [{:keys [imports module-aliases symbol-aliases] :as acc} line]
     (cond
       (re-find py-from-import-re line)
       (let [[_ from names] (re-find py-from-import-re line)
             from (py-normalize-relative-module module from)
             parts (->> (str/split names #",")
                        (map str/trim)
                        (remove str/blank?))
             imports* (into imports [from])
             symbol-aliases* (reduce (fn [m part]
                                       (let [[_ name alias] (or (re-find #"^([A-Za-z0-9_\*]+)(?:\s+as\s+([A-Za-z0-9_]+))?$" part)
                                                                [nil part nil])
                                             local (or alias name)]
                                         (if (= name "*")
                                           m
                                           (assoc m local (str from "/" name)))))
                                     symbol-aliases
                                     parts)]
         {:imports imports*
          :module-aliases module-aliases
          :symbol-aliases symbol-aliases*})

       (re-find py-import-re line)
       (let [[_ imp alias] (re-find py-import-re line)]
         {:imports (conj imports imp)
          :module-aliases (cond-> module-aliases
                            (seq alias) (assoc alias imp))
          :symbol-aliases symbol-aliases})

       :else
       acc))
   {:imports [] :module-aliases {} :symbol-aliases {}}
   lines))

(defn- py-expand-module-alias [token module-aliases]
  (let [token* (str token)]
    (if-let [[_ alias suffix] (re-matches #"([A-Za-z_][A-Za-z0-9_]*)\.(.+)" token*)]
      (when-let [base (get module-aliases alias)]
        (str base "." suffix))
      nil)))

(defn- py-expand-self-token [token module class-name]
  (let [token* (str token)]
    (if-let [[_ _owner suffix] (re-matches #"(self|cls)\.(.+)" token*)]
      (let [base (str module "." class-name)]
        [(str base "." suffix) (str base "/" suffix)])
      [])))

(defn- py-expand-local-class-token [token module local-class-names]
  (let [token* (str token)]
    (if-let [[_ cls suffix] (re-matches #"([A-Za-z_][A-Za-z0-9_]*)\.(.+)" token*)]
      (when (contains? local-class-names cls)
        (let [base (str module "." cls)]
          [(str base "." suffix) (str base "/" suffix)]))
      [])))

(defn- py-expand-symbol-import [token symbol-aliases local-call-names]
  (when (not (contains? local-call-names (str token)))
    (when-let [resolved (get symbol-aliases (str token))]
      [(str resolved)
       (str/replace (str resolved) #"/" ".")])))

(defn- py-local-call-names [defs]
  (->> defs
       (keep :raw-symbol)
       (map (fn [symbol]
              (let [s (str symbol)]
                (cond
                  (str/includes? s "/") (last (str/split s #"/" 2))
                  (str/includes? s ".") (last (str/split s #"\."))
                  :else s))))
       (remove str/blank?)
       set))

(defn- py-local-body-scope [body-lines base-indent]
  (loop [remaining body-lines
         scope-stack []
         acc {:local-call-names #{}
              :local-class-names #{}}]
    (if-let [line (first remaining)]
      (let [trimmed (str/trim line)
            indent (py-indent line)
            scope-stack* (->> scope-stack
                              (filter #(< (:indent %) indent))
                              vec)]
        (cond
          (or (str/blank? trimmed)
              (str/starts-with? trimmed "#")
              (<= indent base-indent))
          (recur (rest remaining) scope-stack* acc)

          (re-find py-def-re line)
          (let [[_ fn-name] (re-find py-def-re line)
                parent-scope (last scope-stack*)
                immediate-local? (or (empty? scope-stack*)
                                     (and (= 1 (count scope-stack*))
                                          (= :class (:kind parent-scope))
                                          (:immediate-local? parent-scope)))]
            (recur (rest remaining)
                   (conj scope-stack* {:indent indent
                                       :kind :def
                                       :immediate-local? immediate-local?})
                   (if immediate-local?
                     (update acc :local-call-names conj fn-name)
                     acc)))

          (re-find py-class-re line)
          (let [[_ cls] (re-find py-class-re line)
                immediate-local? (empty? scope-stack*)]
            (recur (rest remaining)
                   (conj scope-stack* {:indent indent
                                       :kind :class
                                       :immediate-local? immediate-local?})
                   (if immediate-local?
                     (update acc :local-class-names conj cls)
                     acc)))

          :else
          (recur (rest remaining) scope-stack* acc)))
      acc)))

(defn- extract-py-calls [body {:keys [module class-name module-aliases symbol-aliases local-call-names local-class-names body-local-call-names body-local-class-names]}]
  (->> (re-seq py-call-re body)
       (map second)
       (mapcat (fn [token]
                 (let [token* (str token)
                       local-body-class? (some->> (re-matches #"([A-Za-z_][A-Za-z0-9_]*)\.(.+)" token*)
                                                  second
                                                  (contains? body-local-class-names))
                       local-body-call? (contains? body-local-call-names token*)]
                   (if (or local-body-call? local-body-class?)
                     []
                     (let [module-alias-token (py-expand-module-alias token* module-aliases)
                           imported-symbols (py-expand-symbol-import token* symbol-aliases local-call-names)
                           self-symbols (if (and class-name module)
                                          (py-expand-self-token token* module class-name)
                                          [])
                           class-symbols (if module
                                           (py-expand-local-class-token token* module local-class-names)
                                           [])
                           tail (tail-token token*)]
                       (cond-> [token*]
                         (seq module-alias-token) (conj module-alias-token)
                         (seq imported-symbols) (into imported-symbols)
                         (seq self-symbols) (into self-symbols)
                         (seq class-symbols) (into class-symbols)
                         (and tail (not= tail token*)) (conj tail)))))))
       (remove (fn [token]
                 (let [token* (str token)
                       tail (tail-token token*)
                       local-class-owner? (some->> (re-matches #"([A-Za-z_][A-Za-z0-9_]*)\.(.+)" token*)
                                                   second
                                                   (contains? body-local-class-names))]
                   (or (contains? body-local-call-names token*)
                       (contains? body-local-call-names tail)
                       local-class-owner?))))
       (remove #(contains? py-call-stop %))
       distinct
       vec))
(defn- py-test-target-modules [module imports path]
  (if (py-test-path? path)
    (->> (concat [(py-strip-test-module module)] imports)
         (remove #(or (str/blank? %)
                      (= % "unittest")
                      (= % "pytest")))
         distinct
         vec)
    []))

(defn parse-file [_root-path path lines _parser-opts]
  (let [line-count (count lines)
        module (py-module-name path)
        {:keys [imports module-aliases symbol-aliases]} (py-import-state module lines)
        imports (->> imports distinct vec)
        test-target-modules (py-test-target-modules module imports path)
        defs (loop [idx 0
                    class-stack []
                    fn-stack []
                    out []]
               (if (>= idx line-count)
                 out
                 (let [line (nth lines idx)
                       indent (py-indent line)
                       blank-or-comment? (or (str/blank? (str/trim line))
                                             (str/starts-with? (str/trim line) "#"))
                       pruned (if blank-or-comment?
                                class-stack
                                (->> class-stack
                                     (filter #(< (:indent %) indent))
                                     vec))
                       pruned-fns (if blank-or-comment?
                                    fn-stack
                                    (->> fn-stack
                                         (filter #(< % indent))
                                         vec))
                       inside-function? (seq pruned-fns)]
                   (cond
                     (re-find py-class-re line)
                     (let [[_ cls] (re-find py-class-re line)
                           entry {:start-line (inc idx)
                                  :kind "class"
                                  :raw-symbol (str module "." cls)
                                  :signature (trim-signature line)}]
                       (if inside-function?
                         (recur (inc idx) pruned (conj pruned-fns indent) out)
                         (recur (inc idx) (conj pruned {:name cls :indent indent}) pruned-fns (conj out entry))))

                     (re-find py-def-re line)
                     (let [[_ fn-name] (re-find py-def-re line)
                           class-name (py-in-class-context pruned indent)
                           symbol (if class-name
                                    (str module "." class-name "/" fn-name)
                                    (str module "/" fn-name))
                           kind (if class-name
                                  (if (str/starts-with? (str/lower-case fn-name) "test") "test" "method")
                                  (py-kind path fn-name))
                           entry {:start-line (inc idx)
                                  :kind kind
                                  :raw-symbol symbol
                                  :class-name class-name
                                  :signature (trim-signature line)}]
                       (if inside-function?
                         (recur (inc idx) pruned (conj pruned-fns indent) out)
                         (recur (inc idx) pruned (conj pruned-fns indent) (conj out entry))))

                     :else
                     (recur (inc idx) pruned pruned-fns out)))))
        local-call-names (py-local-call-names defs)
        local-class-names (->> defs
                               (filter #(= "class" (:kind %)))
                               (keep (fn [{:keys [raw-symbol]}]
                                       (some-> raw-symbol str (str/split #"\.") last)))
                               set)
        starts (mapv :start-line defs)
        ends (unit-end-lines starts line-count)
        units (->> (map vector defs ends)
                   (map (fn [[d end-line]]
                          (let [start-line (:start-line d)
                                body-lines (subvec lines (dec start-line) end-line)
                                body (str/join "\n" body-lines)
                                body-scope (py-local-body-scope body-lines (py-indent (nth lines (dec start-line))))]
                            {:unit_id (str path "::" (:raw-symbol d))
                             :kind (:kind d)
                             :symbol (:raw-symbol d)
                             :path path
                             :module module
                             :start_line start-line
                             :end_line end-line
                             :signature (:signature d)
                             :summary (str (:kind d) " " (:raw-symbol d))
                             :docstring_excerpt nil
                             :imports imports
                             :calls (extract-py-calls body {:module module
                                                            :class-name (:class-name d)
                                                            :module-aliases module-aliases
                                                            :symbol-aliases symbol-aliases
                                                            :local-call-names local-call-names
                                                            :local-class-names local-class-names
                                                            :body-local-call-names (:local-call-names body-scope)
                                                            :body-local-class-names (:local-class-names body-scope)})
                             :parser_mode "full"})))
                   vec)]
    {:language "python"
     :module module
     :imports imports
     :test_target_modules test-target-modules
     :units units
     :diagnostics []
     :parser_mode "full"}))
