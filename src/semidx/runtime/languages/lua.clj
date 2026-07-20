(ns semidx.runtime.languages.lua
  (:require [clojure.string :as str]
            [semidx.runtime.languages.shared :as shared]))

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

(def ^:private lua-call-stop
  #{"if" "for" "while" "repeat" "until" "function" "local" "return" "end"
    "elseif" "require"})

(defn- trim-signature [line]
  (shared/trim-signature line))

(defn- tail-token [token]
  (shared/tail-token token))

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

(defn parse-file [_root-path path lines _parser-opts]
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
