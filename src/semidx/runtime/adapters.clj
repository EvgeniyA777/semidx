(ns semidx.runtime.adapters
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [semidx.runtime.languages.clojure :as clj-language]
            [semidx.runtime.languages.css :as css-language]
            [semidx.runtime.languages.html :as html-language]
            [semidx.runtime.languages.javascript :as js-language]
            [semidx.runtime.languages.java :as java-language]
            [semidx.runtime.languages.shared :as shared-language]
            [semidx.runtime.languages.typescript :as ts-language]
            [semidx.runtime.language-registry :as language-registry]
            [semidx.runtime.semantic-ir :as semantic-ir]))

(def ^:private py-import-re #"^\s*import\s+([a-zA-Z0-9_\.]+)(?:\s+as\s+([A-Za-z0-9_]+))?")
(def ^:private py-from-import-re #"^\s*from\s+([a-zA-Z0-9_\.]+)\s+import\s+([A-Za-z0-9_,\s\*_]+)")
(def ^:private py-class-re #"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)")
(def ^:private py-def-re #"^\s*(?:async\s+def|def)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
(def ^:private py-call-re #"\b([A-Za-z_][A-Za-z0-9_\.]*)\s*\(")
(declare py-normalize-relative-module)

(def ^:private lua-require-re #"(?:^|[^A-Za-z0-9_])require\s*(?:\(\s*['\"]([^'\"]+)['\"]\s*\)|['\"]([^'\"]+)['\"])")
(def ^:private lua-assigned-require-re #"^\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*require\s*(?:\(\s*['\"]([^'\"]+)['\"]\s*\)|['\"]([^'\"]+)['\"])")
(def ^:private lua-local-function-re #"^\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
(def ^:private lua-local-assigned-function-re #"^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\(")
(def ^:private lua-function-re #"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
(def ^:private lua-assigned-function-re #"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\(")
(def ^:private lua-module-function-re #"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\(")
(def ^:private lua-module-method-re #"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\:([A-Za-z_][A-Za-z0-9_]*)\s*\(")
(def ^:private lua-table-assigned-function-re #"^\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\(")
(def ^:private lua-call-re #"\b([A-Za-z_][A-Za-z0-9_]*)(?:(\.|:)([A-Za-z_][A-Za-z0-9_]*))?\s*\(")

(def ^:private ts-import-clause-re #"^\s*import\s+(.+?)\s+from\s+['\"]([^'\"]+)['\"]")
(def ^:private ts-import-bare-re #"^\s*import\s+['\"]([^'\"]+)['\"]")
(def ^:private ts-class-re #"^\s*(?:export\s+)?(?:default\s+)?class\s+([A-Za-z_$][A-Za-z0-9_$]*)")
(def ^:private ts-function-re #"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(")
(def ^:private ts-arrow-re #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][A-Za-z0-9_$]*)\s*=>")
(def ^:private ts-function-expression-re #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:async\s*)?function\b")
(def ^:private ts-method-re #"^\s*(?:(?:public|private|protected|static|async|readonly|get|set)\s+)*([A-Za-z_$][A-Za-z0-9_$]*)\s*\([^;]*\)\s*(?::\s*[^\{=]+)?\s*\{")
(def ^:private ts-class-field-arrow-re #"^\s*(?:(?:public|private|protected|static|async|readonly)\s+)*([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][A-Za-z0-9_$]*)\s*(?::\s*[^\{=]+)?\s*=>")
(def ^:private ts-object-start-re #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*\{")
(def ^:private ts-object-method-re #"^\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\([^;]*\)\s*(?::\s*[^\{=]+)?\s*\{")
(def ^:private ts-call-re #"\b([A-Za-z_$][A-Za-z0-9_$\.]*)\s*\(")

(def ^:private py-call-stop
  #{"if" "for" "while" "return" "yield" "lambda" "class" "def" "print"})

(def ^:private lua-call-stop
  #{"if" "for" "while" "repeat" "until" "function" "local" "return" "end"
    "elseif" "require"})

(def ^:private ts-call-stop
  #{"if" "for" "while" "switch" "catch" "return" "throw" "new" "super" "this"
    "function" "class" "import" "export" "typeof" "instanceof" "await" "delete"
    "do" "try" "finally" "of" "in"})

(defn language-by-path [path]
  (language-registry/language-by-path path))

(defn source-path? [path]
  (language-registry/source-path? path))

(defn- slurp-lines [file]
  (shared-language/slurp-lines file))

(defn- trim-signature [line]
  (shared-language/trim-signature line))

(defn- unit-end-lines [starts total-lines]
  (shared-language/unit-end-lines starts total-lines))

(defn- tail-token [token]
  (shared-language/tail-token token))

(defn- safe-line [lines n]
  (shared-language/safe-line lines n))

(defn- ts-strip-ext [path]
  (-> (str path)
      (str/replace #"\.(ts|tsx|js|jsx|mjs|cjs)$" "")
      (str/replace #"/index$" "")))

(defn- ts-module-name [path]
  (-> path
      str
      (str/replace "\\" "/")
      ts-strip-ext
      (str/replace #"^\./+" "")
      (str/replace #"^/+" "")
      (str/replace #"/" ".")
      (str/replace #"^\.+|\.+$" "")))

(defn- ts-resolve-import-path [path spec]
  (let [spec* (str spec)]
    (if (str/starts-with? spec* ".")
      (let [dir (or (some-> path io/file .getParent) "")
            joined (if (str/blank? dir) spec* (str dir "/" spec*))]
        (-> joined io/file .toPath .normalize str (str/replace "\\" "/")))
      (str/replace spec* "\\" "/"))))

(defn- ts-parse-named-imports [clause]
  (let [body (some-> (re-find #"\{([^}]*)\}" (str clause)) second)]
    (reduce
     (fn [acc part]
       (let [part* (-> part str/trim (str/replace #"^type\s+" ""))]
         (if (str/blank? part*)
           acc
           (let [[_ exported local] (or (re-find #"^([A-Za-z_$][A-Za-z0-9_$]*)(?:\s+as\s+([A-Za-z_$][A-Za-z0-9_$]*))?$" part*)
                                        [nil part* nil])]
             (assoc acc (or local exported) exported)))))
     {}
     (str/split (or body "") #","))))

(defn- ts-import-state [path lines]
  (reduce
   (fn [{:keys [imports module-aliases symbol-aliases default-aliases] :as acc} line]
     (if-let [[_ clause spec] (re-find ts-import-clause-re line)]
       (let [resolved (-> (ts-resolve-import-path path spec) ts-module-name)
             clause* (str/trim clause)
             default-alias (when-not (or (str/starts-with? clause* "{")
                                         (str/starts-with? clause* "*"))
                             (some-> (re-find #"^(?:type\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:,|$)" clause*) second))
             namespace-alias (some-> (re-find #"\*\s+as\s+([A-Za-z_$][A-Za-z0-9_$]*)" clause*) second)
             named-aliases (ts-parse-named-imports clause*)]
         {:imports (conj imports resolved)
          :module-aliases (cond-> module-aliases
                            (seq namespace-alias) (assoc namespace-alias resolved))
          :symbol-aliases (reduce-kv (fn [m local exported]
                                       (assoc m local (str resolved "/" exported)))
                                     symbol-aliases
                                     named-aliases)
          :default-aliases (cond-> default-aliases
                             (seq default-alias) (assoc default-alias (str resolved "/default")))})
       (if-let [[_ spec] (re-find ts-import-bare-re line)]
         (update acc :imports conj (-> (ts-resolve-import-path path spec) ts-module-name))
         acc)))
   {:imports [] :module-aliases {} :symbol-aliases {} :default-aliases {}}
   lines))

(defn- ts-default-export-line? [line]
  (boolean (re-find #"^\s*export\s+default\s+" (str line))))

(defn- tree-sitter-available? []
  (shared-language/tree-sitter-available?))

(defn- parser-grammar-path [parser-opts lang]
  (shared-language/parser-grammar-path parser-opts lang))

(defn- tree-sitter-cst [abs-path grammar-path]
  (shared-language/tree-sitter-cst abs-path grammar-path))

(defn- add-tree-sitter-diag [parsed enabled? language]
  (shared-language/add-tree-sitter-diag parsed enabled? language))

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

(defn parse-python-file [path lines]
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

(def ^:private lua-default-export-owners
  #{"M" "_M" "module"})

(defn- lua-strip-ext [path]
  (-> (str path)
      (str/replace #"\.lua$" "")
      (str/replace #"/init$" "")))

(defn- lua-module-name [path]
  (-> path
      str
      (str/replace "\\" "/")
      lua-strip-ext
      (str/replace #"^\./+" "")
      (str/replace #"^/+" "")
      (str/replace #"/" ".")
      (str/replace #"^\.+|\.+$" "")))

(defn- lua-normalize-import [spec]
  (-> (str spec)
      (str/replace "\\" "/")
      lua-strip-ext
      (str/replace #"/" ".")))

(defn- lua-strip-line-comment [line]
  (first (str/split (str line) #"(?s)--" 2)))

(defn- lua-block-delta [line]
  (let [line* (lua-strip-line-comment line)
        opens (+ (count (re-seq #"\bfunction\b" line*))
                 (count (re-seq #"\bif\b" line*))
                 (count (re-seq #"\bfor\b" line*))
                 (count (re-seq #"\bwhile\b" line*))
                 (count (re-seq #"\brepeat\b" line*)))
        closes (+ (count (re-seq #"\bend\b" line*))
                  (count (re-seq #"\buntil\b" line*)))]
    (- opens closes)))

(defn- lua-line-start-depths [lines]
  (loop [remaining lines
         depth 0
         depths []]
    (if-let [line (first remaining)]
      (recur (rest remaining)
             (max 0 (+ depth (lua-block-delta line)))
             (conj depths depth))
      depths)))

(defn- lua-unit-end-line [lines start-line]
  (let [line-count (count lines)
        start-idx (max 0 (dec start-line))]
    (loop [idx start-idx
           depth 0]
      (if (>= idx line-count)
        line-count
        (let [next-depth (+ depth (lua-block-delta (nth lines idx)))]
          (if (and (> idx start-idx) (<= next-depth 0))
            (inc idx)
            (recur (inc idx) next-depth)))))))

(defn- lua-test-path? [path]
  (let [p (str/lower-case (str path))]
    (or (str/includes? p "/test/")
        (str/includes? p "/tests/")
        (str/ends-with? p "_test.lua")
        (str/ends-with? p "_spec.lua")
        (str/starts-with? (last (str/split p #"/")) "test_"))))

(defn- lua-kind [path fn-name method?]
  (if (or (lua-test-path? path)
          (str/starts-with? (str/lower-case (or fn-name "")) "test"))
    "test"
    (if method? "method" "function")))

(defn- lua-strip-test-module [module]
  (let [m (str module)]
    (cond
      (str/ends-with? m "_test") (subs m 0 (- (count m) 5))
      (str/ends-with? m "_spec") (subs m 0 (- (count m) 5))
      :else m)))

(defn- lua-test-target-modules [module imports path]
  (if (lua-test-path? path)
    (->> (concat [(lua-strip-test-module module)] imports)
         (remove str/blank?)
         distinct
         vec)
    []))

(defn- lua-import-state [lines]
  (reduce
   (fn [{:keys [imports module-aliases] :as acc} line]
     (cond
       (re-find lua-assigned-require-re line)
       (let [[_ alias spec-a spec-b] (re-find lua-assigned-require-re line)
             spec (lua-normalize-import (or spec-a spec-b))]
         {:imports (conj imports spec)
          :module-aliases (assoc module-aliases alias spec)})

       (re-find lua-require-re line)
       (let [[_ spec-a spec-b] (re-find lua-require-re line)
             spec (lua-normalize-import (or spec-a spec-b))]
         (update acc :imports conj spec))

       :else
       acc))
   {:imports [] :module-aliases {}}
   lines))

(defn- lua-export-owner [lines line-start-depths]
  (->> (map-indexed vector lines)
       (keep (fn [[idx line]]
               (when (zero? (nth line-start-depths idx 1))
                 (some-> (re-find #"^\s*return\s+([A-Za-z_][A-Za-z0-9_]*)\s*$"
                                  (lua-strip-line-comment line))
                         second))))
       last))

(defn- lua-owner-module [module owner export-owner]
  (let [owner* (str owner)]
    (if (or (= owner* export-owner)
            (and (str/blank? (or export-owner ""))
                 (contains? lua-default-export-owners owner*)))
      module
      (str module "." owner*))))

(defn- lua-local-call-names [defs]
  (->> defs
       (keep (comp tail-token :raw-symbol))
       (remove str/blank?)
       set))

(defn- lua-body-local-call-names [body-lines]
  (->> (map-indexed vector body-lines)
       (keep (fn [[idx line]]
               (when (pos? idx)
                 (or (some-> (re-find lua-local-function-re line) second)
                     (some-> (re-find lua-local-assigned-function-re line) second)))))
       (remove str/blank?)
       set))

(defn- extract-lua-calls
  [body {:keys [module-aliases owner-modules current-owner-module body-local-call-names]}]
  (->> (re-seq lua-call-re body)
       (mapcat (fn [[_ owner separator member]]
                 (let [owner* (str owner)
                       member* (some-> member str)
                       base-token (cond
                                    (= separator ":") (str owner* "#" member*)
                                    (= separator ".") (str owner* "." member*)
                                    :else owner*)
                       expanded-owner (or (when (= owner* "self") current-owner-module)
                                          (get module-aliases owner*)
                                          (get owner-modules owner*))
                       expanded-tokens (cond
                                         (and expanded-owner (= separator ".") (seq member*))
                                         [(str expanded-owner "." member*)
                                          (str expanded-owner "/" member*)]

                                         (and expanded-owner (= separator ":") (seq member*))
                                         [(str expanded-owner "#" member*)
                                          (str expanded-owner "." member*)]

                                         :else [])
                       raw-qualified (cond-> []
                                       (and (= separator ".") (seq member*)) (conj (str owner* "/" member*))
                                       (and (= separator ":") (seq member*)) (conj (str owner* "." member*)))]
                   (if (or (contains? lua-call-stop owner*)
                           (contains? body-local-call-names owner*)
                           (and (seq member*) (contains? body-local-call-names member*)))
                     []
                     (cond-> [base-token]
                       (seq raw-qualified) (into raw-qualified)
                       (seq expanded-tokens) (into expanded-tokens)
                       (and (seq member*) (not= member* base-token)) (conj member*))))))
       (remove #(contains? lua-call-stop (str %)))
       distinct
       vec))

(defn- lua-def-record [module export-owner path line-no line]
  (cond
    (re-find lua-module-method-re line)
    (let [[_ owner fn-name] (re-find lua-module-method-re line)
          owner-module (lua-owner-module module owner export-owner)]
      {:start-line line-no
       :kind (lua-kind path fn-name true)
       :raw-symbol (str owner-module "#" fn-name)
       :module owner-module
       :owner owner
       :signature (trim-signature line)})

    (re-find lua-module-function-re line)
    (let [[_ owner fn-name] (re-find lua-module-function-re line)
          owner-module (lua-owner-module module owner export-owner)]
      {:start-line line-no
       :kind (lua-kind path fn-name false)
       :raw-symbol (str owner-module "/" fn-name)
       :module owner-module
       :owner owner
       :signature (trim-signature line)})

    (re-find lua-table-assigned-function-re line)
    (let [[_ owner fn-name] (re-find lua-table-assigned-function-re line)
          owner-module (lua-owner-module module owner export-owner)]
      {:start-line line-no
       :kind (lua-kind path fn-name false)
       :raw-symbol (str owner-module "/" fn-name)
       :module owner-module
       :owner owner
       :signature (trim-signature line)})

    (re-find lua-local-function-re line)
    (let [[_ fn-name] (re-find lua-local-function-re line)]
      {:start-line line-no
       :kind (lua-kind path fn-name false)
       :raw-symbol (str module "/" fn-name)
       :module module
       :signature (trim-signature line)})

    (re-find lua-local-assigned-function-re line)
    (let [[_ fn-name] (re-find lua-local-assigned-function-re line)]
      {:start-line line-no
       :kind (lua-kind path fn-name false)
       :raw-symbol (str module "/" fn-name)
       :module module
       :signature (trim-signature line)})

    (re-find lua-function-re line)
    (let [[_ fn-name] (re-find lua-function-re line)]
      {:start-line line-no
       :kind (lua-kind path fn-name false)
       :raw-symbol (str module "/" fn-name)
       :module module
       :signature (trim-signature line)})

    (re-find lua-assigned-function-re line)
    (let [[_ fn-name] (re-find lua-assigned-function-re line)]
      {:start-line line-no
       :kind (lua-kind path fn-name false)
       :raw-symbol (str module "/" fn-name)
       :module module
       :signature (trim-signature line)})

    :else nil))

(defn- parse-lua [path lines]
  (let [module (lua-module-name path)
        line-start-depths (lua-line-start-depths lines)
        {:keys [imports module-aliases]} (lua-import-state lines)
        imports (->> imports distinct vec)
        export-owner (lua-export-owner lines line-start-depths)
        defs (->> (map-indexed vector lines)
                  (keep (fn [[idx line]]
                          (when (zero? (nth line-start-depths idx 1))
                            (lua-def-record module export-owner path (inc idx) line))))
                  vec)
        owner-modules (->> defs
                           (keep (fn [{:keys [owner module]}]
                                   (when (and (seq owner) (seq module))
                                     [owner module])))
                           (into {}))
        local-call-names (lua-local-call-names defs)
        test-target-modules (lua-test-target-modules module imports path)
        units (->> defs
                   (mapv (fn [d]
                           (let [start-line (:start-line d)
                                 end-line (lua-unit-end-line lines start-line)
                                 body-lines (subvec lines (dec start-line) end-line)
                                 body (str/join "\n" body-lines)
                                 body-local-call-names (lua-body-local-call-names body-lines)]
                             {:unit_id (str path "::" (:raw-symbol d))
                              :kind (:kind d)
                              :symbol (:raw-symbol d)
                              :path path
                              :module (:module d)
                              :start_line start-line
                              :end_line end-line
                              :signature (:signature d)
                              :summary (str (:kind d) " " (:raw-symbol d))
                              :docstring_excerpt nil
                              :imports imports
                              :calls (extract-lua-calls body {:module-aliases module-aliases
                                                              :owner-modules owner-modules
                                                              :current-owner-module (:module d)
                                                              :local-call-names local-call-names
                                                              :body-local-call-names body-local-call-names})
                              :parser_mode "full"}))))]
    {:language "lua"
     :module module
     :imports imports
     :test_target_modules test-target-modules
     :units units
     :diagnostics []
     :parser_mode "full"}))

(defn parse-lua-file [path lines]
  (parse-lua path lines))

(defn- ts-test-path? [path]
  (language-registry/ecmascript-test-path? path))

(defn- ts-kind [path name method?]
  (if (or (ts-test-path? path)
          (str/starts-with? (str/lower-case (or name "")) "test"))
    "test"
    (if method? "method" "function")))

(defn- ts-class-ranges [lines]
  (let [line-count (count lines)]
    (loop [idx 0
           out []]
      (if (>= idx line-count)
        out
        (let [line (nth lines idx)]
          (if-let [[_ cls] (re-find ts-class-re line)]
            (let [end-line
                  (loop [j idx
                         depth 0
                         saw-open? false]
                    (if (>= j line-count)
                      line-count
                      (let [ln (nth lines j)
                            open-n (count (re-seq #"\{" ln))
                            close-n (count (re-seq #"\}" ln))
                            saw-open?* (or saw-open? (pos? open-n))
                            depth* (+ depth open-n (- close-n))]
                        (if (and saw-open?* (<= depth* 0))
                          (inc j)
                          (recur (inc j) depth* saw-open?*)))))
                  range {:class cls
                         :start-line (inc idx)
                         :end-line (max (inc idx) end-line)}]
              (recur (inc idx) (conj out range)))
            (recur (inc idx) out)))))))

(defn- ts-class-for-line [class-ranges line-no]
  (->> class-ranges
       (filter #(<= (:start-line %) line-no (:end-line %)))
       (sort-by :start-line)
       last))

(defn- ts-object-ranges [lines]
  (let [line-count (count lines)]
    (loop [idx 0
           out []]
      (if (>= idx line-count)
        out
        (let [line (nth lines idx)]
          (if-let [[_ obj] (re-find ts-object-start-re line)]
            (let [end-line
                  (loop [j idx
                         depth 0
                         saw-open? false]
                    (if (>= j line-count)
                      line-count
                      (let [ln (nth lines j)
                            open-n (count (re-seq #"\{" ln))
                            close-n (count (re-seq #"\}" ln))
                            saw-open?* (or saw-open? (pos? open-n))
                            depth* (+ depth open-n (- close-n))]
                        (if (and saw-open?* (<= depth* 0))
                          (inc j)
                          (recur (inc j) depth* saw-open?*)))))
                  range {:object obj
                         :start-line (inc idx)
                         :end-line (max (inc idx) end-line)}]
              (recur (inc idx) (conj out range)))
            (recur (inc idx) out)))))))

(defn- ts-object-for-line [object-ranges line-no]
  (->> object-ranges
       (filter #(<= (:start-line %) line-no (:end-line %)))
       (sort-by :start-line)
       last))

(defn- ts-local-call-names [defs]
  (->> defs
       (keep :raw-symbol)
       (map (fn [symbol]
              (let [s (str symbol)]
                (cond
                  (str/includes? s "#") (last (str/split s #"#"))
                  (str/includes? s "/") (last (str/split s #"/" 2))
                  :else s))))
       (remove str/blank?)
       set))

(defn- ts-expand-module-alias [token module-aliases]
  (let [token* (str token)]
    (when-let [[_ alias suffix] (re-matches #"([A-Za-z_$][A-Za-z0-9_$]*)\.(.+)" token*)]
      (when-let [base (get module-aliases alias)]
        (str base "." suffix)))))

(defn- ts-expand-symbol-import [token symbol-aliases local-call-names]
  (let [token* (str token)]
    (when (not (contains? local-call-names token*))
      (when-let [resolved (get symbol-aliases token*)]
        [(str resolved)
         (str/replace (str resolved) #"/" ".")]))))

(defn- ts-expand-default-import [token default-aliases local-call-names]
  (let [token* (str token)]
    (when (not (contains? local-call-names token*))
      (when-let [resolved (get default-aliases token*)]
        [(str resolved)
         (str/replace (str resolved) #"/" ".")]))))

(defn- ts-expand-this-token [token owner-module]
  (let [token* (str token)]
    (if-let [[_ _ suffix] (re-matches #"(this|super)\.(.+)" token*)]
      [(str owner-module "#" suffix)
       (str owner-module "." suffix)]
      [])))

(defn- ts-expand-local-class-token [token file-module local-class-names]
  (let [token* (str token)]
    (if-let [[_ cls suffix] (re-matches #"([A-Za-z_$][A-Za-z0-9_$]*)\.(.+)" token*)]
      (when (contains? local-class-names cls)
        (let [base (str file-module "." cls)]
          [(str base "#" suffix)
           (str base "." suffix)]))
      [])))

(defn- ts-expand-local-object-token [token file-module local-object-names]
  (let [token* (str token)]
    (if-let [[_ obj suffix] (re-matches #"([A-Za-z_$][A-Za-z0-9_$]*)\.(.+)" token*)]
      (when (contains? local-object-names obj)
        (let [base (str file-module "." obj)]
          [(str base "#" suffix)
           (str base "." suffix)]))
      [])))

(defn- extract-ts-calls [body {:keys [owner-module file-module module-aliases symbol-aliases
                                      default-aliases local-call-names local-class-names local-object-names]}]
  (->> (re-seq ts-call-re body)
       (map second)
       (mapcat (fn [token]
                 (let [module-alias-token (ts-expand-module-alias token module-aliases)
                       imported-symbols (ts-expand-symbol-import token symbol-aliases local-call-names)
                       imported-defaults (ts-expand-default-import token default-aliases local-call-names)
                       this-symbols (if (seq owner-module)
                                      (ts-expand-this-token token owner-module)
                                      [])
                       class-symbols (if (seq file-module)
                                       (ts-expand-local-class-token token file-module local-class-names)
                                       [])
                       object-symbols (if (seq file-module)
                                        (ts-expand-local-object-token token file-module local-object-names)
                                        [])
                       tail (tail-token token)]
                   (cond-> [token]
                     (seq module-alias-token) (conj module-alias-token)
                     (seq imported-symbols) (into imported-symbols)
                     (seq imported-defaults) (into imported-defaults)
                     (seq this-symbols) (into this-symbols)
                     (seq class-symbols) (into class-symbols)
                     (seq object-symbols) (into object-symbols)
                     (and tail (not= tail token)) (conj tail)))))
       (remove #(contains? ts-call-stop %))
       distinct
       vec))

(defn- parse-typescript-regex [path lines]
  (let [line-count (count lines)
        module (ts-module-name path)
        {:keys [imports module-aliases symbol-aliases default-aliases]} (ts-import-state path lines)
        imports (->> imports distinct vec)
        class-ranges (ts-class-ranges lines)
        object-ranges (ts-object-ranges lines)
        default-export-aliases (->> lines
                                    (keep #(some-> (re-find #"^\s*export\s+default\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*;?\s*$" %) second))
                                    set)
        re-export-defs (->> lines
                            (keep (fn [line]
                                    (when-let [[_ exported alias spec] (re-find #"^\s*export\s+\{\s*([A-Za-z_$][A-Za-z0-9_$]*)(?:\s+as\s+([A-Za-z_$][A-Za-z0-9_$]*))?\s*\}\s+from\s+['\"]([^'\"]+)['\"]" line)]
                                      (let [resolved (-> (ts-resolve-import-path path spec) ts-module-name)
                                            alias* (or alias exported)
                                            target (if (= "default" exported)
                                                     (str resolved "/default")
                                                     (str resolved "/" exported))]
                                        {:start-line (inc (.indexOf lines line))
                                         :kind "function"
                                         :raw-symbol (str module "/" alias*)
                                         :module module
                                         :signature (trim-signature line)
                                         :call_tokens (cond-> []
                                                        (= "default" alias*) (conj (str module "/default")))
                                         :synthetic-calls [target]}))))
                            vec)
        defs (->> (map-indexed vector lines)
                  (keep (fn [[idx line]]
                          (let [line-no (inc idx)
                                class-ctx (ts-class-for-line class-ranges line-no)]
                            (cond
                              (and (nil? class-ctx) (re-find ts-function-re line))
                              (let [[_ fn-name] (re-find ts-function-re line)]
                                {:start-line line-no
                                 :kind (ts-kind path fn-name false)
                                 :raw-symbol (str module "/" fn-name)
                                 :call_tokens (cond-> []
                                                (ts-default-export-line? line) (conj (str module "/default")))
                                 :module module
                                 :signature (trim-signature line)})

                              (and (nil? class-ctx) (re-find ts-arrow-re line))
                              (let [[_ fn-name] (re-find ts-arrow-re line)]
                                {:start-line line-no
                                 :kind (ts-kind path fn-name false)
                                 :raw-symbol (str module "/" fn-name)
                                 :module module
                                 :signature (trim-signature line)})

                              (and (nil? class-ctx) (re-find ts-function-expression-re line))
                              (let [[_ fn-name] (re-find ts-function-expression-re line)]
                                {:start-line line-no
                                 :kind (ts-kind path fn-name false)
                                 :raw-symbol (str module "/" fn-name)
                                 :module module
                                 :signature (trim-signature line)})

                              (and class-ctx (re-find ts-method-re line))
                              (let [[_ method-name] (re-find ts-method-re line)]
                                (when-not (or (contains? ts-call-stop method-name)
                                              (= "constructor" method-name))
                                  {:start-line line-no
                                   :kind (ts-kind path method-name true)
                                   :raw-symbol (str module "." (:class class-ctx) "#" method-name)
                                   :class-name (:class class-ctx)
                                   :module (str module "." (:class class-ctx))
                                   :signature (trim-signature line)}))

                              (and class-ctx (re-find ts-class-field-arrow-re line))
                              (let [[_ method-name] (re-find ts-class-field-arrow-re line)]
                                {:start-line line-no
                                 :kind (ts-kind path method-name true)
                                 :raw-symbol (str module "." (:class class-ctx) "#" method-name)
                                 :class-name (:class class-ctx)
                                 :module (str module "." (:class class-ctx))
                                 :signature (trim-signature line)})

                              (and (nil? class-ctx)
                                   (ts-object-for-line object-ranges line-no)
                                   (re-find ts-object-method-re line))
                              (let [object-ctx (ts-object-for-line object-ranges line-no)
                                    [_ method-name] (re-find ts-object-method-re line)]
                                {:start-line line-no
                                 :kind "function"
                                 :raw-symbol (str module "." (:object object-ctx) "#" method-name)
                                 :object-name (:object object-ctx)
                                 :module (str module "." (:object object-ctx))
                                 :signature (trim-signature line)})

                              :else nil))))
                  vec)
        defs (vec (concat defs re-export-defs))
        local-call-names (ts-local-call-names defs)
        local-class-names (->> class-ranges
                               (keep :class)
                               set)
        local-object-names (->> object-ranges
                                (keep :object)
                                set)
        starts (mapv :start-line defs)
        ends (unit-end-lines starts line-count)
        units (->> (map vector defs ends)
                   (map (fn [[d end-line]]
                          (let [start-line (:start-line d)
                                body-lines (subvec lines (dec start-line) end-line)
                                body (str/join "\n" body-lines)]
                            {:unit_id (str path "::" (:raw-symbol d))
                             :kind (:kind d)
                             :symbol (:raw-symbol d)
                             :path path
                             :module (:module d)
                             :start_line start-line
                             :end_line end-line
                             :signature (:signature d)
                             :summary (str (:kind d) " " (:raw-symbol d))
                             :docstring_excerpt nil
                             :imports imports
                             :call_tokens (cond-> (vec (:call_tokens d))
                                            (contains? default-export-aliases
                                                       (last (str/split (str (:raw-symbol d)) #"[#/]" 2)))
                                            (conj (str module "/default")))
                             :calls (vec (distinct (concat (extract-ts-calls body {:owner-module (:module d)
                                                                                   :file-module module
                                                                                   :module-aliases module-aliases
                                                                                   :symbol-aliases symbol-aliases
                                                                                   :default-aliases default-aliases
                                                                                   :local-call-names local-call-names
                                                                                   :local-class-names local-class-names
                                                                                   :local-object-names local-object-names})
                                                           (:synthetic-calls d))))
                             :parser_mode "full"})))
                   vec)]
    {:language "typescript"
     :module module
     :imports imports
     :units units
     :diagnostics []
     :parser_mode "full"}))

(defn- ts-node-type [node]
  (let [node-type (str (:node-type node))
        txt (str (:text node))]
    (if (str/ends-with? node-type ":")
      (or (some-> (re-find #":\s*([A-Za-z_][A-Za-z0-9_]*)" txt) second)
          node-type)
      node-type)))

(defn- ts-node-values-inside [ts-lines node]
  (->> ts-lines
       (filter #(<= (:start-row node) (:start-row %) (:end-row node)))
       (filter #(< (:indent node) (:indent %)))
       (filter #(contains? #{"identifier" "property_identifier" "type_identifier"} (ts-node-type %)))
       (keep :value)
       (remove str/blank?)
       vec))

(defn- ts-named-value-inside [ts-lines node marker]
  (->> ts-lines
       (filter #(<= (:start-row node) (:start-row %) (:end-row node)))
       (filter #(< (:indent node) (:indent %)))
       (filter #(contains? #{"identifier" "property_identifier" "type_identifier"} (ts-node-type %)))
       (filter #(str/includes? (:text %) marker))
       (keep :value)
       (remove str/blank?)
       first))

(defn- parse-typescript-tree-sitter [root-path path src-lines parser-opts]
  (let [grammar-path (parser-grammar-path parser-opts :typescript)
        abs (-> (io/file root-path path) .getCanonicalPath)
        module (ts-module-name path)
        {:keys [imports module-aliases symbol-aliases default-aliases]} (ts-import-state path src-lines)
        imports (->> imports distinct vec)]
    (cond
      (not (tree-sitter-available?))
      {:ok? false
       :reason {:code "tree_sitter_unavailable"
                :summary "tree-sitter CLI is unavailable for typescript tree-sitter parser."}}

      (str/blank? (str grammar-path))
      {:ok? false
       :reason {:code "tree_sitter_missing_grammar"
                :summary "No tree-sitter TypeScript grammar path configured."}}

      :else
      (let [{:keys [ok? lines err]} (tree-sitter-cst abs grammar-path)
            ts-lines lines]
        (if-not ok?
          {:ok? false
           :reason {:code "tree_sitter_parse_failed"
                    :summary (str "tree-sitter parse failed: " (subs (str err) 0 (min 220 (count (str err)))))}}
          (let [class-nodes (->> ts-lines
                                 (filter #(= "class_declaration" (ts-node-type %)))
                                 (map (fn [c]
                                        (assoc c :class-name
                                               (or (ts-named-value-inside ts-lines c "name:")
                                                   (some-> (ts-node-values-inside ts-lines c) first)
                                                   "UnknownClass"))))
                                 vec)
                class-for-row (fn [row]
                                (->> class-nodes
                                     (filter #(<= (:start-row %) row (:end-row %)))
                                     (sort-by :start-row)
                                     last))
                local-class-names (->> class-nodes
                                       (keep :class-name)
                                       set)
                fn-defs (->> ts-lines
                             (filter #(= "function_declaration" (ts-node-type %)))
                             (map (fn [n]
                                    (let [nm (or (ts-named-value-inside ts-lines n "name:")
                                                 (some-> (ts-node-values-inside ts-lines n) first)
                                                 "unknownFunction")
                                          start-line (inc (:start-row n))
                                          end-line (inc (:end-row n))]
                                      {:start-line (inc (:start-row n))
                                       :end-line (inc (:end-row n))
                                       :kind (ts-kind path nm false)
                                       :symbol (str module "/" nm)
                                       :call_tokens (cond-> []
                                                      (ts-default-export-line? (safe-line src-lines start-line))
                                                      (conj (str module "/default")))
                                       :module module
                                       :file-module module
                                       :calls (extract-ts-calls (str/join "\n" (subvec src-lines (dec start-line) end-line))
                                                                {:owner-module module
                                                                 :file-module module
                                                                 :module-aliases module-aliases
                                                                 :symbol-aliases symbol-aliases
                                                                 :default-aliases default-aliases
                                                                 :local-call-names #{}
                                                                 :local-class-names local-class-names})})))
                             vec)
                arrow-defs (->> ts-lines
                                (filter #(= "variable_declarator" (ts-node-type %)))
                                (keep (fn [n]
                                        (let [has-callable? (some (fn [child]
                                                                    (and (<= (:start-row n) (:start-row child) (:end-row n))
                                                                         (< (:indent n) (:indent child))
                                                                         (contains? #{"arrow_function" "function_expression"} (ts-node-type child))))
                                                                  ts-lines)]
                                          (when has-callable?
                                            (let [nm (or (ts-named-value-inside ts-lines n "name:")
                                                         (some-> (ts-node-values-inside ts-lines n) first)
                                                         "unknownArrow")
                                                  start-line (inc (:start-row n))
                                                  end-line (inc (:end-row n))]
                                              {:start-line start-line
                                               :end-line end-line
                                               :kind (ts-kind path nm false)
                                               :symbol (str module "/" nm)
                                               :module module
                                               :file-module module
                                               :calls (extract-ts-calls (str/join "\n" (subvec src-lines (dec start-line) end-line))
                                                                        {:owner-module module
                                                                         :file-module module
                                                                         :module-aliases module-aliases
                                                                         :symbol-aliases symbol-aliases
                                                                         :default-aliases default-aliases
                                                                         :local-call-names #{}
                                                                         :local-class-names local-class-names})})))))
                                vec)
                method-defs (->> ts-lines
                                 (filter #(= "method_definition" (ts-node-type %)))
                                 (keep (fn [n]
                                         (let [class-ctx (class-for-row (:start-row n))
                                               nm (or (ts-named-value-inside ts-lines n "name:")
                                                      (some-> (ts-node-values-inside ts-lines n) first))]
                                           (when (and class-ctx (seq nm) (not= "constructor" nm))
                                             (let [owner-module (str module "." (:class-name class-ctx))
                                                   start-line (inc (:start-row n))
                                                   end-line (inc (:end-row n))]
                                               {:start-line start-line
                                                :end-line end-line
                                                :kind (ts-kind path nm true)
                                                :symbol (str owner-module "#" nm)
                                                :module owner-module
                                                :file-module module
                                                :calls (extract-ts-calls (str/join "\n" (subvec src-lines (dec start-line) end-line))
                                                                         {:owner-module owner-module
                                                                          :file-module module
                                                                          :module-aliases module-aliases
                                                                          :symbol-aliases symbol-aliases
                                                                          :default-aliases default-aliases
                                                                          :local-call-names #{}
                                                                          :local-class-names local-class-names})})))))
                                 vec)
                defs (->> (concat fn-defs arrow-defs method-defs)
                          (sort-by (juxt :start-line :symbol))
                          distinct
                          vec)
                local-call-names (ts-local-call-names (map #(assoc % :raw-symbol (:symbol %)) defs))
                units (->> defs
                           (map (fn [{:keys [start-line end-line kind symbol module file-module call_tokens]}]
                                  {:unit_id (str path "::" symbol)
                                   :kind kind
                                   :symbol symbol
                                   :path path
                                   :module module
                                   :start_line start-line
                                   :end_line (max start-line end-line)
                                   :signature (safe-line src-lines start-line)
                                   :summary (str kind " " symbol)
                                   :docstring_excerpt nil
                                   :imports imports
                                   :call_tokens (vec call_tokens)
                                   :calls (extract-ts-calls (str/join "\n" (subvec src-lines (dec start-line) end-line))
                                                            {:owner-module module
                                                             :file-module file-module
                                                             :module-aliases module-aliases
                                                             :symbol-aliases symbol-aliases
                                                             :default-aliases default-aliases
                                                             :local-call-names local-call-names
                                                             :local-class-names local-class-names})
                                   :parser_mode "full"}))
                           vec)]
            (if (seq units)
              {:ok? true
               :result {:language "typescript"
                        :module module
                        :imports imports
                        :units units
                        :diagnostics [{:code "tree_sitter_active"
                                       :summary "TypeScript analyzed using tree-sitter CST extraction."}]
                        :parser_mode "full"}}
              {:ok? false
               :reason {:code "tree_sitter_no_units"
                        :summary "tree-sitter did not extract TypeScript units."}})))))))

(defn- parse-typescript-legacy [root-path path lines {:keys [typescript_engine tree_sitter_enabled]
                                                      :or {typescript_engine :regex}
                                                      :as parser-opts}]
  (let [engine (if (true? tree_sitter_enabled) :tree-sitter typescript_engine)
        parsed (if (= engine :tree-sitter)
                 (let [{:keys [ok? result reason]} (parse-typescript-tree-sitter root-path path lines parser-opts)]
                   (if ok?
                     result
                     (-> (parse-typescript-regex path lines)
                         (update :diagnostics conj reason))))
                 (parse-typescript-regex path lines))]
    (add-tree-sitter-diag parsed tree_sitter_enabled "typescript")))

(defn- parse-typescript [root-path file-path lines parser-opts]
  (try
    (ts-language/parse-file root-path file-path lines parser-opts)
    (catch Exception _
      (parse-typescript-legacy root-path file-path lines parser-opts))))

(defn- fallback-unit [path lines language reason]
  (let [line-count (max 1 (count lines))]
    {:language (or language "unknown")
     :module nil
     :imports []
     :units [{:unit_id (str path "::fallback")
              :kind "section"
              :symbol (str path "::fallback")
              :path path
              :module nil
              :start_line 1
              :end_line line-count
              :signature (if (seq lines) (trim-signature (first lines)) "")
              :summary "fallback section"
              :docstring_excerpt nil
              :imports []
              :calls []
              :parser_mode "fallback"}]
     :diagnostics [{:code "parser_fallback" :summary reason}]
     :parser_mode "fallback"}))

(defn- parse-elixir-language-file [root-path file-path lines parser-opts]
  ((requiring-resolve 'semidx.runtime.languages.elixir/parse-file)
   root-path
   file-path
   lines
   parser-opts))

(defn- parse-html [root-path file-path lines parser-opts]
  (html-language/parse-file root-path file-path lines parser-opts))

(defn- parse-css [root-path file-path lines parser-opts]
  (css-language/parse-file root-path file-path lines parser-opts))

(defn- parse-javascript [root-path file-path lines parser-opts]
  (js-language/parse-file root-path file-path lines parser-opts))

(defn parse-file
  ([root-path file-path] (parse-file root-path file-path {}))
  ([root-path file-path parser-opts]
   (let [abs (io/file root-path file-path)
         language (language-by-path file-path)]
     (try
       (let [lines (slurp-lines abs)]
         (->> (case language
                "clojure" (clj-language/parse-file root-path file-path lines parser-opts)
                "java" (java-language/parse-file root-path file-path lines parser-opts)
                "elixir" (parse-elixir-language-file root-path file-path lines parser-opts)
                "python" (parse-python-file file-path lines)
                "typescript" (parse-typescript root-path file-path lines parser-opts)
                "javascript" (parse-javascript root-path file-path lines parser-opts)
                "lua" (parse-lua file-path lines)
                "html" (parse-html root-path file-path lines parser-opts)
                "css" (parse-css root-path file-path lines parser-opts)
                (fallback-unit file-path lines language "unsupported_language"))
              (semantic-ir/finalize-parsed-file file-path language)))
       (catch Exception _
         (let [lines (try (slurp-lines abs) (catch Exception _ []))]
           (semantic-ir/finalize-parsed-file
            file-path
            language
            (fallback-unit file-path lines language "parse_exception"))))))))
