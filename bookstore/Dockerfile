FROM eclipse-temurin:11-jre
WORKDIR /app
COPY target/epub-reader-server-1.0.0.jar app.jar
RUN mkdir -p /app/uploads/books /app/uploads/covers
EXPOSE 8002
ENV SPRING_PROFILES_ACTIVE=prod
ENTRYPOINT ["java","-jar","/app/app.jar"]
