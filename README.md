# Banking System Console (phase 1, educational simulation)

Simulated banking only. Not connected to real payment infrastructure.

## Status
- frontend/index.html : interactive UI preview (sample data, no backend). Works now.
- backend/ : Spring Boot skeleton + MySQL schema + atomic TransferService.
  NOT yet verified to compile. No login, controllers, or tests yet.

## Run the UI preview
VS Code -> install "Live Server" -> right-click frontend/index.html -> Open with Live Server.
(Or just double-click index.html.)

## Run the backend (needs JDK 17+, Maven, MySQL 8)
1. mysql -u root -p -e "CREATE DATABASE bank_console; CREATE USER 'bank_app'@'localhost' IDENTIFIED BY 'change-me'; GRANT ALL ON bank_console.* TO 'bank_app'@'localhost';"
2. cd backend
3. Set env vars (see .env.example): DB_URL, DB_USERNAME, DB_PASSWORD, JWT_SECRET (32+ random chars)
   macOS/Linux: export JWT_SECRET=$(openssl rand -hex 32)
   Windows PowerShell: $env:JWT_SECRET="your-long-random-secret"
4. mvn spring-boot:run
5. Check http://localhost:8080/actuator/health and http://localhost:8080/swagger-ui/index.html
Flyway creates all tables from db/migration/V1__init.sql on first start.

## VS Code extensions
Extension Pack for Java, Spring Boot Extension Pack, Live Server.
