(ns demo.greeter)

(def greeting "hi there")

(defn greet []
  (str greeting "!"))

(defn announce []
  (greet)
  (report))
