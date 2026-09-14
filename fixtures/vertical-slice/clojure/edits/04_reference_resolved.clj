(ns demo.greeter)

(def greeting "hello")

(defn greet []
  (str greeting "!"))

(defn report []
  "reported")

(defn announce []
  (greet)
  (report))
