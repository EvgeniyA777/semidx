(ns demo.greeter)

(def greeting "hello")

(defn greet []
  (str greeting "!"))

(defn announce []
  (greet)
  (report))
