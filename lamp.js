(function () {
    var plugin_id = "macro_lampa"; 
    console.log(`[${plugin_id}] Плагин запущен`);

    var server_url = "http://192.168.0.1:8080/lampa"; // HTTP-сервер MacroDroid

    function checkMacroDroid() {
        fetch(server_url)
            .then(res => res.json())
            .then(data => {
                console.log(`[${plugin_id}] Данные от MacroDroid:`, data);
                if (data.q) {
                    console.log(`[${plugin_id}] Получен фильм: ${data.q}`);
                    searchMovie(data.q);
                }
            })
            .catch(err => console.error(`[${plugin_id}] Ошибка запроса:`, err));
    }

    function searchMovie(query) {
        console.log(`[${plugin_id}] Запускаем поиск: ${query}`);
        Lampa.Activity.backward();
        setTimeout(() => {
            Lampa.Activity.push({
                url: "",
                title: "Поиск",
                component: "search"
            });

            setTimeout(() => {
                let searchInput = document.querySelector(".search__input");
                if (searchInput) {
                    console.log(`[${plugin_id}] Вставляем текст: ${query}`);
                    searchInput.value = query;
                    searchInput.dispatchEvent(new Event("input", { bubbles: true }));

                    let enterEvent = new KeyboardEvent("keydown", { key: "Enter", bubbles: true });
                    searchInput.dispatchEvent(enterEvent);
                } else {
                    console.log(`[${plugin_id}] Поле поиска не найдено!`);
                }
            }, 1500);
        }, 1000);
    }

    setInterval(checkMacroDroid, 5000); // Проверяем сервер каждые 5 секунд

    console.log(`[${plugin_id}] Плагин успешно загружен!`);
})();
