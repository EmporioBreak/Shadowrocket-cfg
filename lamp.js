(function () {
    var plugin_id = "webhook_search"; // Уникальный ID плагина
    console.log(`[${plugin_id}] Плагин загружен`);

    // URL вебхука (можно поменять на свой сервер)
    var webhook_url = "http://192.168.0.151/test";

    // Функция для выполнения поиска
    function searchMovie(query) {
        console.log(`[${plugin_id}] Запрос на поиск: ${query}`);
        Lampa.Activity.backward(); // Закрываем текущее окно
        setTimeout(() => {
            Lampa.Controller.toggle("search"); // Открываем поиск
            setTimeout(() => {
                let searchInput = document.querySelector(".search__input"); // Поле ввода в Lampa
                if (searchInput) {
                    searchInput.value = query;
                    searchInput.dispatchEvent(new Event("input", { bubbles: true })); // Запускаем событие ввода
                    console.log(`[${plugin_id}] Введён текст в поиск: ${query}`);
                } else {
                    console.log(`[${plugin_id}] Поле поиска не найдено!`);
                }
            }, 500);
        }, 500);
    }

    // Функция проверки вебхука
    function checkWebhook() {
        fetch(webhook_url)
            .then(response => response.json())
            .then(data => {
                if (data.query) {
                    console.log(`[${plugin_id}] Получен текст: ${data.query}`);
                    searchMovie(data.query);
                }
            })
            .catch(error => console.log(`[${plugin_id}] Ошибка вебхука:`, error));
    }

    // Проверяем вебхук каждые 5 секунд
    setInterval(checkWebhook, 5000);

    console.log(`[${plugin_id}] Плагин успешно активирован!`);
})();
