(ns semidx.storage-test
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [next.jdbc :as jdbc]
            [semidx.core :as sci]
            [semidx.runtime.storage :as storage]))

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(defn- sample-root! []
  (let [root (str (java.nio.file.Files/createTempDirectory "semidx-storage" (make-array java.nio.file.attribute.FileAttribute 0)))]
    (write-file! root "src/my/app/core.clj" "(ns my.app.core)\n(defn run [] :ok)\n")
    root))

(deftest postgres-init-storage-adds-repo-identity-columns-and-indexes-test
  (let [statements (atom [])
        storage-adapter (storage/map->PostgresStorage {:datasource ::fake})]
    (with-redefs [jdbc/execute! (fn [_ sqlvec]
                                  (swap! statements conj (first sqlvec))
                                  [])]
      (storage/init-storage! storage-adapter))
    (testing "snapshot table includes additive identity columns"
      (is (some #(str/includes? % "repo_key text") @statements))
      (is (some #(str/includes? % "workspace_path text") @statements))
      (is (some #(str/includes? % "workspace_key text") @statements))
      (is (some #(str/includes? % "git_branch text") @statements))
      (is (some #(str/includes? % "git_commit text") @statements))
      (is (some #(str/includes? % "git_dirty boolean") @statements))
      (is (some #(str/includes? % "identity_source text") @statements)))
    (testing "repo-aware indexes are created additively"
      (is (some #(str/includes? % "idx_semantic_index_snapshots_repo_key_id") @statements))
      (is (some #(str/includes? % "idx_semantic_index_snapshots_repo_branch_id") @statements))
      (is (some #(str/includes? % "idx_semantic_index_snapshots_repo_commit") @statements)))))

(deftest save-index-tx-writes-repo-identity-metadata-into-snapshot-row-test
  (let [root (sample-root!)
        index (sci/create-index {:root_path root})
        statements (atom [])]
    (with-redefs [jdbc/execute! (fn [_ sqlvec]
                                  (swap! statements conj sqlvec)
                                  [])]
      (#'semidx.runtime.storage/save-index-tx! ::fake-tx index))
    (let [snapshot-insert (first @statements)]
      (testing "snapshot insert persists additive repo metadata"
        (is (str/includes? (first snapshot-insert) "repo_key"))
        (is (= (:root_path index) (nth snapshot-insert 1)))
        (is (= (:snapshot_id index) (nth snapshot-insert 2)))
        (is (= (:repo_key index) (nth snapshot-insert 3)))
        (is (= (:workspace_path index) (nth snapshot-insert 4)))
        (is (= (:workspace_key index) (nth snapshot-insert 5)))
        (is (= (:git_branch index) (nth snapshot-insert 6)))
        (is (= (:git_commit index) (nth snapshot-insert 7)))
        (is (= (:git_dirty index) (nth snapshot-insert 8)))
        (is (= (:identity_source index) (nth snapshot-insert 9)))))))
