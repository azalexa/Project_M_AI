# MechMaster

**Prototyp platformy ogłoszeń o usterkach i usługach naprawczych, zbudowany w oparciu o Microsoft Azure.**

> **Status projektu: archiwalny / infrastruktura w trakcie wycofywania (23 listopada 2026 r.).** Repozytorium dokumentuje zrealizowany prototyp i proces jego budowy. Nie należy zakładać, że dawny adres strony, API lub logowanie nadal działają.

## Cel projektu

MechMaster miał łączyć osoby, które potrzebują pomocy w naprawie, z osobami oferującymi usługi lub posiadającymi odpowiednie umiejętności. Przykłady: samochód, który nie chce odpalić, cieknący kran, uszkodzona pralka, awaria instalacji elektrycznej albo problem z komputerem.

Projekt rozpoczął się od prostego testu hostingu statycznego. W kolejnych iteracjach powstała platforma ogłoszeń z systemem kont, interfejsem użytkownika i backendem zapisującym dane w Azure. Nazwa repozytorium `Project_M_AI` pochodzi z etapu prac; **nie wdrożono produkcyjnego modułu sztucznej inteligencji**.

## Zakres funkcjonalny prototypu

| Funkcja | Stan osiągnięty w projekcie |
| --- | --- |
| Responsywna strona z kategoriami napraw | Zaimplementowana |
| Ogłoszenia „Potrzebuję pomocy” i „Oferuję pomoc” | Zaimplementowane |
| Wyszukiwanie i filtrowanie ogłoszeń | Zaimplementowane |
| Rejestracja i logowanie użytkowników | Zintegrowane z Microsoft Entra External ID |
| Publikowanie ogłoszeń do wspólnej bazy danych | Uruchomione i przetestowane ręcznie |
| Odpowiedzi na ogłoszenia | Zaimplementowane w API |
| Prywatne wiadomości między użytkownikami | Zaimplementowane w API; brak pełnego potwierdzenia testu między dwoma kontami |
| Zamykanie własnych ogłoszeń | Zaimplementowane w API |
| Automatyczna publikacja frontendu | Uruchomiona przez Azure Pipelines |
| Automatyczna publikacja backendu przez pipeline | Nieukończona; backend publikowano osobnym skryptem |

## Architektura

| Warstwa | Technologia | Rola |
| --- | --- | --- |
| Frontend | HTML, CSS, JavaScript | Interfejs użytkownika |
| Uwierzytelnianie | Microsoft Entra External ID, MSAL | Konta użytkowników, logowanie, tokeny |
| API | Azure Functions, Node.js | Operacje na ogłoszeniach, odpowiedziach i wiadomościach |
| Dane aplikacji | Azure Table Storage | Ogłoszenia, odpowiedzi i rozmowy |
| Dostęp API do danych | Managed Identity i Azure RBAC | Autoryzacja bez przechowywania kluczy Storage w przeglądarce |
| Hosting frontendu | Azure Storage Static Website | Udostępnianie plików strony |
| CI/CD frontendu | GitHub i Azure Pipelines | Publikacja po zmianach w gałęzi `main` |

Przepływ działania: **przeglądarka → frontend → token Microsoft Entra → Azure Functions → Azure Table Storage**.

Konta i hasła były obsługiwane przez Entra External ID, a nie przez tabelę SQL. Dodatkowo utworzono serwer **Azure Database for PostgreSQL Flexible Server**, lecz używany backend ogłoszeń nie miał skonfigurowanego połączenia z PostgreSQL. Nie był on wymagany do funkcjonowania prototypu.

## Struktura repozytorium

| Ścieżka | Zawartość |
| --- | --- |
| `frontend/` | Strona, style, JavaScript i konfiguracja logowania oraz API |
| `api/` | Azure Functions, logika biznesowa, walidacja, autoryzacja i testy |
| `scripts/` | Skrypty PowerShell do tworzenia zasobów i publikowania API |
| `azure-pipelines.yml` | Automatyczny deployment statycznego frontendu |

## API

Zaimplementowano następujące trasy (prefiks `/api`):

| Metoda | Trasa | Cel |
| --- | --- | --- |
| `GET` | `/health` | Kontrola dostępności API |
| `GET` | `/posts` | Lista ogłoszeń |
| `POST` | `/posts` | Dodanie ogłoszenia |
| `PATCH` | `/posts/{id}` | Zmiana statusu ogłoszenia |
| `GET` | `/posts/{id}/responses` | Odpowiedzi na ogłoszenie |
| `POST` | `/posts/{id}/responses` | Dodanie odpowiedzi |
| `GET` | `/posts/{id}/responses/{respondentId}/messages` | Wiadomości w rozmowie |
| `POST` | `/posts/{id}/responses/{respondentId}/messages` | Wysłanie wiadomości |

Operacje wymagające tożsamości użytkownika były zabezpieczane tokenem Bearer. Backend weryfikował podpis, wystawcę, odbiorcę i zakres uprawnień tokenu, a przy wiadomościach sprawdzał uczestników rozmowy. Sam poziom `anonymous` w definicji Azure Functions nie oznaczał braku autoryzacji: weryfikacja użytkownika była wykonywana w kodzie aplikacji.

## Testy i potwierdzone osiągnięcia

1. Frontend został opublikowany na Azure Storage i działał pod adresem testowym.
2. Azure Pipelines poprawnie automatyzował wdrożenia z gałęzi `main`.
3. Utworzono katalog klientów Microsoft Entra External ID oraz proces rejestracji i logowania.
4. Wdrożono Azure Functions; endpoint `/api/health` zwracał poprawną odpowiedź.
5. Testy jednostkowe i integracyjne API przechodziły po poprawieniu problemu z obsługą ścieżek Windows w mockach.
6. Po publikacji frontendu z konfiguracją API potwierdzono ręcznie możliwość dodania ogłoszenia.

Nie przeprowadzono pełnej walidacji produkcyjnej, testów obciążeniowych ani audytu bezpieczeństwa.

## Napotkane problemy i wnioski

1. **Uprawnienia Storage:** konto dewelopera i tożsamość Azure Pipelines wymagały osobnych ról `Storage Blob Data Contributor`.
2. **Konfiguracja MSAL:** błędny adres `authority` uniemożliwiał pobieranie metadanych OpenID; poprawiono adres z identyfikatorem katalogu.
3. **Testy na Windows:** test integracyjny wymagał poprawki dopasowania ścieżki pliku.
4. **Azure Functions:** lokalne narzędzia wymagały jawnie określonego środowiska Node.js.
5. **Bezpieczeństwo Storage:** wyłączone uwierzytelnianie kluczem wymagało wdrożenia opartego na Managed Identity i korekty starych ustawień deploymentu.
6. **Oddzielenie danych:** tożsamości pozostawały w Entra, natomiast ogłoszenia i wiadomości w Table Storage.

## Uruchomienie ponownie

Kod stanowi dokumentację historyczną, a nie gotowy instalator działającego środowiska. Do ponownego uruchomienia potrzebne będą aktywna subskrypcja Azure, nowa konfiguracja Microsoft Entra External ID, konto Storage, Azure Functions, role RBAC i aktualizacja identyfikatorów oraz adresów w plikach konfiguracyjnych i skryptach.

Lokalne testy API, po zainstalowaniu Node.js i zależności, uruchamia się w katalogu `api`:

```powershell
cd api
npm install
npm test
```

**Nie należy uruchamiać skryptów wdrożeniowych bez sprawdzenia ich parametrów.** Mogą odwoływać się do historycznych identyfikatorów i nazw usuniętych zasobów oraz generować opłaty za usługi Azure.

## Bezpieczeństwo i ograniczenia

Projekt był prototypem MVP, nie publicznie gotowym produktem. Przed wdrożeniem produkcyjnym należałoby dodać monitoring i alerty, kopie zapasowe, ochronę przed spamem, limity zapytań, moderację treści, obsługę zgłoszeń nadużyć, politykę prywatności i retencję danych oraz kompleksowe testy uprawnień i prywatnych rozmów. Do repozytorium **nie należy dodawać haseł, tokenów, kluczy Storage ani plików `local.settings.json`**.

## Zakończenie projektu

W listopadzie 2026 r. rozpoczęto usuwanie zasobów z subskrypcji Azure oraz katalogu klientów Entra. Dla historycznego katalogu External ID usługa Microsoft zwróciła błąd `AADSTS90002` (`Tenant not found`), co wskazuje, że katalog nie był już dostępny pod dotychczasowym identyfikatorem; nie jest to niezależne potwierdzenie zakończenia wszystkich procedur usuwania. Ostateczny stan rozliczeń i wszystkich zasobów wymaga osobnej kontroli w Azure Portal.

**Repozytorium pozostaje zapisem procesu budowania pełnego prototypu webowego na Azure: od statycznej strony, przez tożsamość użytkowników, po działające API i zapis ogłoszeń w chmurze.**
