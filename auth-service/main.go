package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"

	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// App struct (para injeção de dependência)
type App struct {
	DB        *sql.DB
	MasterKey string
}

func main() {
	// Carrega o .env para desenvolvimento local
	_ = godotenv.Load()

	// -----------------------------
	// OpenTelemetry
	// -----------------------------
	shutdown, err := InitTelemetry(context.Background(), "auth-service")
	if err != nil {
		log.Fatalf("Erro ao inicializar OpenTelemetry: %v", err)
	}
	defer shutdown(context.Background())

	// -----------------------------
	// Configuração
	// -----------------------------
	port := os.Getenv("PORT")
	if port == "" {
		port = "8001"
	}

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL deve ser definida")
	}

	masterKey := os.Getenv("MASTER_KEY")
	if masterKey == "" {
		log.Fatal("MASTER_KEY deve ser definida")
	}

	// -----------------------------
	// Banco de Dados
	// -----------------------------
	db, err := connectDB(databaseURL)
	if err != nil {
		log.Fatalf("Não foi possível conectar ao banco de dados: %v", err)
	}
	defer db.Close()

	app := &App{
		DB:        db,
		MasterKey: masterKey,
	}

	// -----------------------------
	// Rotas
	// -----------------------------
	mux := http.NewServeMux()

	mux.HandleFunc("/health", app.healthHandler)

	mux.HandleFunc("/validate", app.validateKeyHandler)

	mux.Handle(
		"/admin/keys",
		app.masterKeyAuthMiddleware(
			http.HandlerFunc(app.createKeyHandler),
		),
	)

	log.Printf("Serviço de Autenticação (Go) rodando na porta %s", port)

	handler := otelhttp.NewHandler(
		mux,
		"http-server",
	)

	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatal(err)
	}
}

// connectDB inicializa e testa a conexão com o PostgreSQL
func connectDB(databaseURL string) (*sql.DB, error) {

	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, err
	}

	if err = db.Ping(); err != nil {
		return nil, err
	}

	log.Println("Conectado ao PostgreSQL com sucesso!")

	return db, nil
}