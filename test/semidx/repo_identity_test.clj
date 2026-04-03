(ns semidx.repo-identity-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [semidx.core :as sci]
            [semidx.runtime.repo-identity :as repo-identity]))

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(defn- sample-root! []
  (let [root (str (java.nio.file.Files/createTempDirectory "semidx-repo-id" (make-array java.nio.file.attribute.FileAttribute 0)))]
    (write-file! root "src/my/app/core.clj" "(ns my.app.core)\n(defn run [] :ok)\n")
    root))

(deftest normalize-remote-url-canonicalizes-ssh-and-https-test
  (is (= "github.com/EvgeniyA777/semidx"
         (repo-identity/normalize-remote-url "git@github.com:EvgeniyA777/semidx.git")))
  (is (= "github.com/EvgeniyA777/semidx"
         (repo-identity/normalize-remote-url "https://github.com/EvgeniyA777/semidx.git"))))

(deftest resolve-repo-identity-prefers-git-remote-test
  (let [root (sample-root!)
        responses {["rev-parse" "--is-inside-work-tree"] {:exit 0 :out "true\n"}
                   ["config" "--get" "remote.origin.url"] {:exit 0 :out "git@github.com:EvgeniyA777/semidx.git\n"}
                   ["rev-parse" "--abbrev-ref" "HEAD"] {:exit 0 :out "dev\n"}
                   ["rev-parse" "HEAD"] {:exit 0 :out "abc123\n"}
                   ["status" "--porcelain"] {:exit 0 :out ""}}]
    (with-redefs [#'repo-identity/run-git (fn [_root-path & args]
                                            (get responses (vec args) {:exit 1 :out "" :err ""}))]
      (let [identity (repo-identity/resolve-repo-identity root)]
        (testing "git remote drives logical repo identity"
          (is (= "git_remote" (:identity_source identity)))
          (is (= "dev" (:git_branch identity)))
          (is (= "abc123" (:git_commit identity)))
          (is (false? (:git_dirty identity)))
          (is (string? (:repo_key identity)))
          (is (string? (:workspace_key identity))))
        (testing "workspace identity stays canonical and local"
          (is (= (.getCanonicalPath (io/file root)) (:workspace_path identity))))))))

(deftest resolve-repo-identity-falls-back-to-repo-id-file-test
  (let [root (sample-root!)]
    (write-file! root ".ccc/repo-id" "repo-123\n")
    (with-redefs [#'repo-identity/run-git (fn [_root-path & _args]
                                            {:exit 1 :out "" :err "not a git repo"})]
      (let [identity (repo-identity/resolve-repo-identity root)]
        (is (= "repo_id_file" (:identity_source identity)))
        (is (string? (:repo_key identity)))
        (is (string? (:workspace_key identity)))
        (is (nil? (:git_branch identity)))
        (is (nil? (:git_commit identity)))
        (is (false? (:git_dirty identity)))))))

(deftest create-index-attaches-repo-identity-metadata-test
  (let [root (sample-root!)
        index (sci/create-index {:root_path root})]
    (testing "top-level snapshot metadata includes repo identity"
      (is (= (.getCanonicalPath (io/file root)) (:workspace_path index)))
      (is (= (:repo_key (:repo_identity index)) (:repo_key index)))
      (is (= (:workspace_key (:repo_identity index)) (:workspace_key index)))
      (is (= (:identity_source (:repo_identity index)) (:identity_source index))))
    (testing "lifecycle summary exposes the additive metadata"
      (is (= (:repo_identity index) (get-in index [:index_lifecycle :repo_identity]))))))

(deftest update-index-preserves-stable-repo-identity-fields-test
  (let [root (sample-root!)
        initial (sci/create-index {:root_path root})]
    (write-file! root "src/my/app/core.clj" "(ns my.app.core)\n(defn run [] :updated)\n")
    (let [updated (sci/update-index initial {:changed_paths ["src/my/app/core.clj"]})]
      (is (= (:repo_key initial) (:repo_key updated)))
      (is (= (:workspace_path initial) (:workspace_path updated)))
      (is (= (:workspace_key initial) (:workspace_key updated)))
      (is (not= (:snapshot_id initial) (:snapshot_id updated))))))
