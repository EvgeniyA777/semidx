package demo;

class Greeter {
    Greeter partner;

    String greeting() {
        return "hi there";
    }

    String greet() {
        return greeting();
    }

    void announce() {
        greet();
        report();
    }
}
