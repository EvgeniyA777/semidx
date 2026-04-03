(ns semidx.runtime.repo-identity
  (:require [clojure.java.io :as io]
            [clojure.java.shell :as sh]
            [clojure.string :as str]
            [semidx.runtime.language-activation :as activation])
  (:import [java.net URI]
           [java.nio.charset StandardCharsets]
           [java.security MessageDigest]))

(def ^:private repo-id-path ".ccc/repo-id")

(defn- sha1-hex [value]
  (let [md (MessageDigest/getInstance "SHA-1")
        bytes (.digest md (.getBytes (str value) StandardCharsets/UTF_8))]
    (apply str (map #(format "%02x" (bit-and % 0xff)) bytes))))

(defn- trim-to-nil [value]
  (let [value* (some-> value str str/trim)]
    (when (seq value*)
      value*)))

(defn- strip-git-suffix [s]
  (str/replace s #"\.git/?$" ""))

(defn normalize-remote-url [remote-url]
  (when-let [remote* (trim-to-nil remote-url)]
    (or
     (try
       (let [uri (URI. remote*)
             host (some-> (.getHost uri) str/lower-case)
             path (some-> (.getPath uri)
                          trim-to-nil
                          strip-git-suffix
                          (str/replace #"^/+" "")
                          (str/replace #"/+$" ""))]
         (when (and (seq host) (seq path))
           (str host "/" path)))
       (catch Exception _
         nil))
     (when-let [[_ host path] (re-matches #"(?i)(?:[^@]+@)?([^:\/]+):/?(.+)" remote*)]
       (let [path* (-> path
                       trim-to-nil
                       strip-git-suffix
                       (str/replace #"^/+" "")
                       (str/replace #"/+$" ""))]
         (when (and (seq host) (seq path*))
           (str (str/lower-case host) "/" path*)))))))

(defn- run-git [root-path & args]
  (apply sh/sh "git" "-C" root-path args))

(defn- git-stdout [root-path & args]
  (let [{:keys [exit out]} (apply run-git root-path args)]
    (when (zero? exit)
      (trim-to-nil out))))

(defn- git-repo? [root-path]
  (= "true" (git-stdout root-path "rev-parse" "--is-inside-work-tree")))

(defn- read-repo-id [root-path]
  (let [repo-id-file (io/file root-path repo-id-path)]
    (when (.exists repo-id-file)
      (trim-to-nil (slurp repo-id-file)))))

(defn resolve-repo-identity [root-path]
  (let [workspace-path (activation/canonical-root-path root-path)
        repo-id (read-repo-id workspace-path)
        git-repo?* (git-repo? workspace-path)
        remote-url (when git-repo?*
                     (git-stdout workspace-path "config" "--get" "remote.origin.url"))
        normalized-remote (normalize-remote-url remote-url)
        identity-source (cond
                          (seq normalized-remote) "git_remote"
                          (seq repo-id) "repo_id_file"
                          :else "root_path_fallback")
        repo-locator (case identity-source
                       "git_remote" (str "remote:" normalized-remote)
                       "repo_id_file" (str "repo-id:" repo-id)
                       (str "workspace:" workspace-path))
        git-branch (when git-repo?*
                     (let [branch (git-stdout workspace-path "rev-parse" "--abbrev-ref" "HEAD")]
                       (when-not (= "HEAD" branch)
                         branch)))
        git-commit (when git-repo?*
                     (git-stdout workspace-path "rev-parse" "HEAD"))
        git-dirty (when git-repo?*
                    (boolean (git-stdout workspace-path "status" "--porcelain")))]
    {:repo_key (sha1-hex repo-locator)
     :workspace_path workspace-path
     :workspace_key (sha1-hex workspace-path)
     :git_branch git-branch
     :git_commit git-commit
     :git_dirty (boolean git-dirty)
     :identity_source identity-source}))
