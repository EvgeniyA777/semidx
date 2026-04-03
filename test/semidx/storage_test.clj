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

(defn- shadow-index [root repo-key workspace-key git-branch git-commit indexed-at]
  (-> (sci/create-index {:root_path root})
      (assoc :repo_key repo-key
             :workspace_path root
             :workspace_key workspace-key
             :git_branch git-branch
             :git_commit git-commit
             :indexed_at indexed-at)))

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

(deftest shadow-repo-lookups-work-across-workspaces-test
  (let [root-a (sample-root!)
        root-b (sample-root!)
        storage-adapter (storage/in-memory-storage)
        repo-key "repo/shared"
        index-a (shadow-index root-a repo-key "workspace-a" "main" "commit-a" "2026-04-03T16:10:00Z")
        index-b (shadow-index root-b repo-key "workspace-b" "feature-x" "commit-b" "2026-04-03T16:11:00Z")]
    (storage/save-index! storage-adapter index-a)
    (storage/save-index! storage-adapter index-b)
    (testing "latest by repo can reuse a newer snapshot from another workspace"
      (is (= (:snapshot_id index-b)
             (:snapshot_id (sci/load-latest-by-repo storage-adapter repo-key)))))
    (testing "repo+branch lookup narrows to the matching branch"
      (is (= (:snapshot_id index-a)
             (:snapshot_id (sci/load-latest-by-repo-branch storage-adapter repo-key "main"))))
      (is (= (:snapshot_id index-b)
             (:snapshot_id (sci/load-latest-by-repo-branch storage-adapter repo-key "feature-x")))))
    (testing "repo+commit lookup resolves the exact snapshot"
      (is (= (:snapshot_id index-a)
             (:snapshot_id (sci/load-by-repo-commit storage-adapter repo-key "commit-a"))))
      (is (= (:snapshot_id index-b)
             (:snapshot_id (sci/load-by-repo-commit storage-adapter repo-key "commit-b")))))))

(deftest create-index-load-latest-remains-root-path-scoped-test
  (let [root-a (sample-root!)
        root-b (sample-root!)
        storage-adapter (storage/in-memory-storage)
        repo-key "repo/shared"
        index-a (shadow-index root-a repo-key "workspace-a" "main" "commit-a" "2026-04-03T16:10:00Z")
        index-b (shadow-index root-b repo-key "workspace-b" "feature-x" "commit-b" "2026-04-03T16:11:00Z")]
    (storage/save-index! storage-adapter index-a)
    (storage/save-index! storage-adapter index-b)
    (let [loaded-a (sci/create-index {:root_path root-a
                                      :storage storage-adapter
                                      :load_latest true})]
      (testing "legacy load_latest still prefers the current workspace root path"
        (is (= (:snapshot_id index-a) (:snapshot_id loaded-a)))
        (is (= (:root_path index-a) (:root_path loaded-a)))
        (is (not= (:snapshot_id index-b) (:snapshot_id loaded-a)))))
      (testing "shadow lookup helpers remain independently available"
        (is (= (:snapshot_id index-b)
               (:snapshot_id (sci/load-latest-by-repo storage-adapter repo-key)))))))
