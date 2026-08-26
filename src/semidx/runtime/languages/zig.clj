(ns semidx.runtime.languages.zig
  (:require [clojure.string :as str]
            [semidx.runtime.languages.shared :as shared]))

(def ^:private zig-import-re #"@import\s*\(\s*\"([^\"]+)\"\s*\)")
(def ^:private zig-assigned-import-re
  #"^\s*(?:pub\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*@import\s*\(\s*\"([^\"]+)\"\s*\)\s*;")
(def ^:private zig-function-re
  #"^\s*(?:(?:pub|export|extern|inline|noinline)\s+)*fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
(def ^:private zig-container-re
  #"^\s*(?:pub\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:packed\s+|extern\s+)?(?:struct|union|enum|opaque)\b[^\{]*\{")
(def ^:private zig-test-re
  #"^\s*test\s+(?:\"([^\"]+)\"|([A-Za-z_][A-Za-z0-9_]*))\s*\{")
(def ^:private zig-call-re #"\b([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*))?\s*\(")

(def ^:private zig-call-stop
  #{"alignCast" "as" "bitCast" "break" "call" "catch" "comptime" "continue"
    "else" "enumFromInt" "error" "export" "extern" "fn" "for" "if" "import"
    "inline" "intCast" "intFromEnum" "max" "min" "noinline" "offsetOf" "panic"
    "ptrCast" "return" "sizeOf" "switch" "test" "try" "typeInfo" "union" "while"})

(defn- trim-signature [line]
  (shared/trim-signature line))

(defn- normalized-path-parts [path]
  (reduce (fn [parts part]
            (cond
              (or (str/blank? part) (= "." part)) parts
              (= ".." part) (if (seq parts) (pop parts) parts)
              :else (conj parts part)))
          []
          (str/split (str/replace (str path) "\\" "/") #"/")))

(defn- strip-zig-extension [path]
  (str/replace (str path) #"\.zig$" ""))

(defn- module-name [path]
  (->> (normalized-path-parts (strip-zig-extension path))
       (str/join ".")))

(defn- parent-path [path]
  (let [path* (str/replace (str path) "\\" "/")
        slash (.lastIndexOf path* "/")]
    (if (neg? slash) "" (subs path* 0 slash))))

(defn- normalize-import [path spec]
  (let [spec* (str/replace (str spec) "\\" "/")
        source-import? (str/ends-with? spec* ".zig")
        resolved (if source-import?
                   (str (parent-path path) "/" spec*)
                   spec*)]
    (->> (normalized-path-parts (strip-zig-extension resolved))
         (str/join "."))))

(defn- strip-line-comment [line]
  (first (str/split (str line) #"//" 2)))

(defn- brace-delta [line]
  (let [line* (strip-line-comment line)]
    (- (count (re-seq #"\{" line*))
       (count (re-seq #"\}" line*)))))

(defn- line-start-depths [lines]
  (loop [remaining lines
         depth 0
         depths []]
    (if-let [line (first remaining)]
      (recur (rest remaining)
             (max 0 (+ depth (brace-delta line)))
             (conj depths depth))
      depths)))

(defn- unit-end-line [lines start-line]
  (let [line-count (count lines)
        start-idx (max 0 (dec start-line))]
    (loop [idx start-idx
           depth 0
           saw-open? false]
      (if (>= idx line-count)
        line-count
        (let [line (nth lines idx)
              delta (brace-delta line)
              saw-open?* (or saw-open? (str/includes? (strip-line-comment line) "{"))
              next-depth (+ depth delta)]
          (if (or (and saw-open?* (<= next-depth 0))
                  (and (= idx start-idx) (not saw-open?*) (str/includes? line ";")))
            (inc idx)
            (recur (inc idx) next-depth saw-open?*)))))))

(defn- test-path? [path]
  (let [path* (-> path str str/lower-case (str/replace "\\" "/"))]
    (or (str/includes? path* "/test/")
        (str/includes? path* "/tests/")
        (str/starts-with? path* "test/")
        (str/starts-with? path* "tests/")
        (str/ends-with? path* "_test.zig")
        (str/ends-with? path* ".test.zig"))))

(defn- strip-test-module [module]
  (cond
    (str/ends-with? module "_test") (subs module 0 (- (count module) 5))
    (str/ends-with? module ".test") (subs module 0 (- (count module) 5))
    :else module))

(defn- test-target-modules [module imports path]
  (if (test-path? path)
    (->> (concat [(strip-test-module module)] imports)
         (remove str/blank?)
         distinct
         vec)
    []))

(defn- import-state [path lines]
  (reduce
   (fn [{:keys [imports aliases] :as state} line]
     (if-let [[_ alias spec] (re-find zig-assigned-import-re line)]
       (let [module (normalize-import path spec)]
         {:imports (conj imports module)
          :aliases (assoc aliases alias module)})
       (if-let [[_ spec] (re-find zig-import-re line)]
         (update state :imports conj (normalize-import path spec))
         state)))
   {:imports [] :aliases {}}
   lines))

(defn- containers [module lines depths]
  (->> (map-indexed vector lines)
       (keep (fn [[idx line]]
               (when-let [[_ name] (re-find zig-container-re line)]
                 (let [start-line (inc idx)]
                   {:name name
                    :module (str module "." name)
                    :depth (nth depths idx 0)
                    :start-line start-line
                    :end-line (unit-end-line lines start-line)}))))
       vec))

(defn- owner-container [container-records line-no depth]
  (->> container-records
       (filter #(and (< (:start-line %) line-no)
                     (<= line-no (:end-line %))
                     (< (:depth %) depth)))
       (sort-by :start-line >)
       first))

(defn- test-name->symbol [module test-name line-no]
  (let [slug (-> (or test-name (str "line-" line-no))
                 str/lower-case
                 (str/replace #"[^a-z0-9]+" "-")
                 (str/replace #"^-+|-+$" ""))]
    (str module "/test-" (if (str/blank? slug) (str "line-" line-no) slug))))

(defn- definition-record [module container-records path depths line-no line]
  (let [depth (nth depths (dec line-no) 0)
        owner (owner-container container-records line-no depth)]
    (cond
      (re-find zig-function-re line)
      (let [[_ name] (re-find zig-function-re line)
            owner-module (:module owner)]
        {:start-line line-no
         :kind (cond
                 (test-path? path) "test"
                 owner "method"
                 :else "function")
         :symbol (if owner
                   (str owner-module "#" name)
                   (str module "/" name))
         :module (or owner-module module)
         :owner (:name owner)
         :name name
         :signature (trim-signature line)})

      (re-find zig-test-re line)
      (let [[_ quoted-name identifier] (re-find zig-test-re line)
            name (or quoted-name identifier)]
        {:start-line line-no
         :kind "test"
         :symbol (test-name->symbol module name line-no)
         :module module
         :name name
         :signature (trim-signature line)})

      :else nil)))

(defn- extract-calls [body {:keys [aliases module owner-module local-names current-name]}]
  (->> (re-seq zig-call-re body)
       (mapcat (fn [[_ owner member]]
                 (let [owner* (str owner)
                       member* (some-> member str)
                       imported-module (get aliases owner*)
                       self-owner? (and owner-module (contains? #{"self" "Self"} owner*))]
                   (cond
                     (or (= owner* current-name)
                         (contains? zig-call-stop owner*))
                     []

                     (seq member*)
                     (cond-> [(str owner* "." member*)
                              (str owner* "/" member*)
                              member*]
                       imported-module (into [(str imported-module "/" member*)
                                              (str imported-module "." member*)])
                       self-owner? (into [(str owner-module "#" member*)
                                          (str owner-module "." member*)]))

                     (contains? local-names owner*)
                     [(str module "/" owner*) owner*]

                     :else [owner*]))))
       (remove str/blank?)
       distinct
       vec))

(defn parse-file [_root-path path lines _parser-opts]
  (let [file-module (module-name path)
        depths (line-start-depths lines)
        {:keys [imports aliases]} (import-state path lines)
        imports (->> imports distinct vec)
        container-records (containers file-module lines depths)
        definitions (->> (map-indexed vector lines)
                         (keep (fn [[idx line]]
                                 (definition-record file-module container-records path depths (inc idx) line)))
                         vec)
        local-names (->> definitions (keep :name) set)
        units (mapv (fn [{:keys [start-line kind symbol module owner name signature]}]
                      (let [end-line (unit-end-line lines start-line)
                            body-lines (subvec lines (min start-line (count lines)) end-line)
                            body (str/join "\n" body-lines)
                            owner-module (when owner module)]
                        {:unit_id (str path "::" symbol)
                         :kind kind
                         :symbol symbol
                         :path path
                         :module module
                         :start_line start-line
                         :end_line end-line
                         :signature signature
                         :summary (str kind " " symbol)
                         :docstring_excerpt nil
                         :imports imports
                         :calls (extract-calls body {:aliases aliases
                                                     :module file-module
                                                     :owner-module owner-module
                                                     :local-names local-names
                                                     :current-name name})
                         :parser_mode "full"}))
                    definitions)]
    {:language "zig"
     :module file-module
     :imports imports
     :test_target_modules (test-target-modules file-module imports path)
     :units units
     :diagnostics []
     :parser_mode "full"}))
