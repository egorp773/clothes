const documents: Record<string, { title: string; body: string[] }> = {
  terms: {
    title: "Пользовательское соглашение",
    body: [
      "Это временная тестовая версия для закрытого тестирования приложения Clothes.",
      "Сервис предоставляет техническую площадку для публикации объявлений и общения пользователей. Реальные платежи и доставка в тестовом контуре не запускаются.",
      "Пользователь обязуется указывать достоверные данные, не публиковать запрещённые товары и не нарушать права других лиц.",
    ],
  },
  privacy_policy: {
    title: "Политика обработки персональных данных",
    body: [
      "Это временная тестовая версия для закрытого тестирования приложения Clothes.",
      "В тестовом контуре обрабатываются данные аккаунта, профиль, объявления и технические сведения, необходимые для работы и безопасности сервиса.",
      "Финальная политика, реквизиты оператора, сроки хранения и перечень обработчиков должны быть утверждены до релиза.",
    ],
  },
  personal_data_consent: {
    title: "Согласие на обработку персональных данных",
    body: [
      "Это временная тестовая версия для закрытого тестирования приложения Clothes.",
      "Пользователь подтверждает согласие на обработку данных, введённых в профиль и созданных при тестировании функций сервиса.",
      "Согласие может быть отозвано через удаление аккаунта или обращение в поддержку после запуска официального канала поддержки.",
    ],
  },
  marketing_consent: {
    title: "Согласие на маркетинговые сообщения",
    body: [
      "Это необязательная временная тестовая версия.",
      "Согласие разрешает отправлять новости продукта и предложения. Отказ не ограничивает регистрацию и использование основных функций.",
    ],
  },
};

Deno.serve((request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: { Allow: "GET, HEAD" },
    });
  }
  const url = new URL(request.url);
  const code = url.searchParams.get("document") ?? "";
  const version = url.searchParams.get("version") ?? "";
  const document = documents[code];
  if (!document || version !== "test-2026-07-26") {
    return new Response("Document not found", { status: 404 });
  }
  const text = [
    "ТОЛЬКО ДЛЯ ЗАКРЫТОГО ТЕСТИРОВАНИЯ",
    "",
    document.title.toUpperCase(),
    "Версия test-2026-07-26",
    "",
    ...document.body.flatMap((item, index) => [`${index + 1}. ${item}`, ""]),
  ].join("\n");
  return new Response(request.method === "HEAD" ? null : text, {
    headers: {
      "Cache-Control": "public, max-age=300",
      "Content-Type": "text/plain; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
    },
  });
});
