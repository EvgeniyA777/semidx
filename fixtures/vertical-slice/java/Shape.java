package demo;

interface Shape {
    String describe();

    default String label() {
        return describe();
    }

    static Shape none() {
        return null;
    }
}
