plugins {
    id("org.jetbrains.kotlin.jvm") version "2.4.0"
}

dependencies {
    api("org.commonmark:commonmark:0.24.0")
    api("org.commonmark:commonmark-ext-gfm-tables:0.24.0")
    api("org.commonmark:commonmark-ext-gfm-strikethrough:0.24.0")
    api("org.commonmark:commonmark-ext-autolink:0.24.0")
    testImplementation("junit:junit:4.13.2")
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnit()
}
