(function () {
    var plugin_id = "macro_lampa";
    console.log(`[${plugin_id}] Плагин загружен!`);

    var server_url = "http://127.0.0.1:8080/lampa";

    function checkMacroDroid() {
        console.log(`[${plugin_id}] Проверяем MacroDroid...`);
        fetch(server_url)
            .then(res => res.json())
            .then(data => {
                console.log(`[${plugin_id}] Получены данные:`, data);
                if (data.q) {
                    console.log(`[${plugin_id}] Запускаем поиск: ${data.q}`);
                    searchMovie(data.q);
                }
            })
            .catch(err => console.error(`[${plugin_id}] Ошибка запроса:`, err));
    }

    function searchMovie(query) {
        console.log(`[${plugin_id}] Открываем окно поиска`);
        
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
    }

    setInterval(checkMacroDroid, 5000);

    Lampa.Plugin.register(plugin_id, () => {
        console.log(`[${plugin_id}] Плагин зарегистрирован в Lampa`);
    });

})();
