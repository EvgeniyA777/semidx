package demo;

class Circle implements Drawable {
    public String describe() {
        return "circle";
    }
}

interface Drawable {
    String describe();
}
