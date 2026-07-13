(ns semidx.freshness-baseline-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [semidx.core :as sci]))

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(deftest freshness-baseline-test
  (let [tmp-root (str (java.nio.file.Files/createTempDirectory "sci-freshness-baseline-test" (make-array java.nio.file.attribute.FileAttribute 0)))
        _ (write-file! tmp-root "src/foo.clj" "(ns foo)\n(defn bar [] :bar)\n")
        storage (sci/in-memory-storage)]
    (testing "create-index on unchanged repo returns same snapshot_id (reuse)"
      (let [idx1 (sci/create-index {:root_path tmp-root :storage storage :load_latest true})
            snap1 (:snapshot_id idx1)
            idx2 (sci/create-index {:root_path tmp-root :storage storage :load_latest true})
            snap2 (:snapshot_id idx2)]
        (is (= snap1 snap2))))

    (testing "create-index after modifying file content returns new snapshot_id"
      (let [idx1 (sci/create-index {:root_path tmp-root :storage storage :load_latest true})
            snap1 (:snapshot_id idx1)
            _ (write-file! tmp-root "src/foo.clj" "(ns foo)\n(defn bar [] :bar-modified)\n")
            idx2 (sci/create-index {:root_path tmp-root :storage storage :load_latest true})
            snap2 (:snapshot_id idx2)]
        (is (not= snap1 snap2))))

    (testing "create-index after adding a file includes the new file in the index"
      (let [idx1 (sci/create-index {:root_path tmp-root :storage storage :load_latest true})
            _ (write-file! tmp-root "src/baz.clj" "(ns baz)\n(defn qux [] :qux)\n")
            idx2 (sci/create-index {:root_path tmp-root :storage storage :load_latest true})]
        (is (contains? (:files idx2) "src/baz.clj"))))

    (testing "create-index after deleting a file excludes it from the index"
      (let [_ (write-file! tmp-root "src/baz.clj" "(ns baz)\n(defn qux [] :qux)\n")
            idx1 (sci/create-index {:root_path tmp-root :storage storage :load_latest true})
            _ (is (contains? (:files idx1) "src/baz.clj"))
            ;; Delete the file
            _ (io/delete-file (io/file tmp-root "src/baz.clj"))
            idx2 (sci/create-index {:root_path tmp-root :storage storage :load_latest true})]
        (is (not (contains? (:files idx2) "src/baz.clj")))))

    (testing "update-index result is semantically equivalent to create-index full rebuild on the same repo state"
      (let [idx-base (sci/create-index {:root_path tmp-root :storage storage :load_latest true})
            ;; Modify a file
            _ (write-file! tmp-root "src/foo.clj" "(ns foo)\n(defn bar [] :bar-updated)\n")
            ;; Run update-index
            idx-updated (sci/update-index idx-base {:changed_paths ["src/foo.clj"] :storage storage})
            ;; Run create-index (full rebuild)
            idx-rebuilt (sci/create-index {:root_path tmp-root :storage storage :force_rebuild true})]
        ;; Files, units, symbol_index keys should match
        (is (= (keys (:files idx-updated)) (keys (:files idx-rebuilt))))
        (is (= (keys (:units idx-updated)) (keys (:units idx-rebuilt))))
        (is (= (keys (:symbol_index idx-updated)) (keys (:symbol_index idx-rebuilt))))))

    (testing "force_rebuild: true always rebuilds regardless of workspace state"
      (let [idx1 (sci/create-index {:root_path tmp-root :storage storage :load_latest true})
            snap1 (:snapshot_id idx1)
            idx2 (sci/create-index {:root_path tmp-root :storage storage :load_latest true :force_rebuild true})
            snap2 (:snapshot_id idx2)]
        (is (not= snap1 snap2))))))
