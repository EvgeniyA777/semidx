(ns semidx.integration.css-onboarding-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [semidx.core :as sci]))

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(defn- tmp-root [prefix]
  (str (java.nio.file.Files/createTempDirectory
        prefix (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- unit-symbols-for-path [index path]
  (->> (:unit_order index)
       (map #(get (:units index) %))
       (filter #(= path (:path %)))
       (map :symbol)
       set))

(defn- provider-for [index path]
  (some->> (get-in index [:workspace_state :files])
           (filter #(= path (:path %)))
           first
           :provider_id))

(deftest css-adapter-onboarding-regression-test
  (let [root (tmp-root "sci-css-onboarding")
        _ (write-file! root "public/index.html"
                       "<main id=\"hero\"><button class=\"cta-button\">Buy</button></main>\n")
        _ (write-file! root "public/styles.css"
                       "@import \"reset.css\";\n:root {\n  --brand-color: #f00;\n}\n#hero { background: url(\"assets/bg.png\"); }\n.cta-button, button.primary { color: var(--brand-color); }\n@media (min-width: 40rem) {\n  .cta-button { padding: 1rem; }\n}\n@keyframes spin {\n  from { opacity: 0; }\n  to { opacity: 1; }\n}\n")
        index (sci/create-index {:root_path root})
        symbols (unit-symbols-for-path index "public/styles.css")]
    (testing "CSS is detected, activated, and provider-tagged"
      (is (= "css" (get-in index [:files "public/styles.css" :language])))
      (is (= "full" (get-in index [:files "public/styles.css" :parser_mode])))
      (is (some #{"css"} (:detected_languages index)))
      (is (some #{"css"} (:active_languages index)))
      (is (= "css-native" (provider-for index "public/styles.css"))))
    (testing "CSS parser extracts selectors, variables, at-rules, and dependencies"
      (is (contains? symbols ".cta-button"))
      (is (contains? symbols "#hero"))
      (is (contains? symbols "--brand-color"))
      (is (contains? symbols "@media"))
      (is (contains? symbols "@keyframes spin"))
      (is (= ["reset.css" "assets/bg.png"]
             (get-in index [:files "public/styles.css" :imports]))))))

(deftest html-css-freshness-regression-test
  (let [root (tmp-root "sci-css-freshness")
        _ (write-file! root "public/index.html" "<main class=\"cta-button\"></main>\n")
        _ (write-file! root "public/styles.css" ".cta-button { color: red; }\n")
        _ (write-file! root "public/theme.css" ":root { --brand-color: red; }\n")
        storage (sci/in-memory-storage)
        first-index (sci/create-index {:root_path root :storage storage :load_latest true})]
    (testing "CSS changes flow through freshness-driven incremental update"
      (write-file! root "public/styles.css" ".cta-button { color: blue; }\n")
      (let [after (sci/create-index {:root_path root :storage storage :load_latest true})]
        (is (not= (:snapshot_id first-index) (:snapshot_id after)))
        (is (= "incremental_update" (get-in after [:index_lifecycle :lifecycle_action])))
        (is (= "css" (get-in after [:files "public/styles.css" :language])))
        (is (some #{"html"} (:active_languages after)))
        (is (some #{"css"} (:active_languages after)))))))
