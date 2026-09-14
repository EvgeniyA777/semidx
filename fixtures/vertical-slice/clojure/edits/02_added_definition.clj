(ns demo.greeter)

(def greeting "hello")

(defn greet []
  (str greeting "!"))

(defn farewell []
  "bye")

(defn announce []
  (greet)
  (report))
