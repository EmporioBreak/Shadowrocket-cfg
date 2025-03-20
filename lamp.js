(function () {
    var plugin_id = "macro_lampa"; // Уникальный ID плагина
    console.log(`[${plugin_id}] Плагин запущен`);

    var server_url = "http://192.168.0.151/lampa"; // IP MacroDroid-сервера

    function checkMacroDroid() {
        fetch(server_url)
            .then(res => res.json())
            .then(data => {
                if (data.q) {
                    console.log(`[${plugin_id}] Команда на поиск: ${data.q}`);
                    searchMovie(data.q);
                }
            })
            .catch(err => console.error(`[${plugin_id}] Ошибка сервера:`, err));
    }

    function searchMovie(query) {
        console.log(`[${plugin_id}] Запускаем поиск: ${query}`);
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

    setInterval(checkMacroDroid, 5000); // Проверяем сервер каждые 5 секунд

    console.log(`[${plugin_id}] Плагин успешно загружен!`);
})();
