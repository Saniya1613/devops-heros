# Two-stage build: compile with the full JDK, run on the slim JRE.
# Stage 1 is discarded, so javac never ships in the final image.

FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /build
COPY Main.java .
RUN javac Main.java

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /build/Main.class .

ENV PORT=7000
EXPOSE 7000

CMD ["java", "Main"]
