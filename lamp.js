(function () {
    var plugin_id = "lampa_http"; // Уникальный ID плагина
    console.log(`[${plugin_id}] Плагин загружен`);

    var server = new Lampa.HttpServer(8181); // Запускаем локальный сервер
    server.start();

    server.onRequest((req, res) => {
        if (req.path === "/search" && req.method === "GET") {
            let query = req.query["q"];
            if (query) {
                searchMovie(query);
                res.sendJSON({ status: "ok", message: "Поиск запущен" });
            } else {
                res.sendJSON({ status: "error", message: "Нет запроса" });
            }
        } else {
            res.sendJSON({ status: "error", message: "Неизвестный запрос" });
        }
    });

    function searchMovie(query) {
        console.log(`[${plugin_id}] Поиск: ${query}`);
        Lampa.Activity.backward();
        setTimeout(() => {
            Lampa.Controller.toggle("search");
            setTimeout(() => {
                let searchInput = document.querySelector(".search__input");
                if (searchInput) {
                    searchInput.value = query;
                    searchInput.dispatchEvent(new Event("input", { bubbles: true }));
                }
            }, 500);
        }, 500);
    }

    console.log(`[${plugin_id}] HTTP-сервер запущен на порту 8181`);
})();
