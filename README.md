# Painel Climático — Salesforce Weather Dashboard

Componente Salesforce (LWC + Apex) que consulta dados meteorológicos em tempo real via **Open-Meteo API** — gratuita, sem necessidade de chave de API.

---

## Visão Geral do Projeto

O **Painel Climático** permite que usuários do Salesforce pesquisem qualquer cidade do mundo e visualizem instantaneamente:

| Métrica | Dado exibido |
|---|---|
| Temperatura | Valor atual em °C |
| Sensação Térmica | Apparent temperature |
| Umidade | Umidade relativa do ar em % |
| Vento | Velocidade do vento a 10 m (km/h) |
| Precipitação | Precipitação atual em mm |

A interface é totalmente em **português brasileiro (pt-BR)**, incluindo rótulos, mensagens de erro e descrições de condições meteorológicas (mapeamento WMO 4677).

Cada consulta realiza duas chamadas HTTP sequenciais:

1. **Geocoding API** — converte o nome da cidade em coordenadas (latitude/longitude), país e fuso horário.
2. **Forecast API** — retorna as condições meteorológicas atuais para as coordenadas obtidas.

### Arquitetura

```
weatherDashboard (LWC)
        │
        │ @AuraEnabled (imperativo)
        ▼
WeatherService.getWeatherByCity(cityName)
        │
        ├─► geocodeCity()  ──► Open-Meteo Geocoding API
        │
        └─► fetchForecast() ─► Open-Meteo Forecast API
                │
                └─► buildWeatherResult() ──► WeatherDTO.WeatherResult
```

**Configuração externalizada** — todos os endpoints e parâmetros da API são armazenados em um Custom Metadata Type (`WeatherAPIConfig__mdt`), sem hardcoding no código-fonte. Isso permite alterar endpoints sem deploy de código.

---

## Pré-requisitos

| Requisito | Detalhe |
|---|---|
| Salesforce CLI | `sf` v2+ (SFDX) |
| API Version | **62.0** (Summer '25) |
| Org Edition | Developer, Sandbox ou qualquer edição com Apex e LWC habilitados |
| Perfil mínimo | Permissão para executar classes Apex e acessar App Pages |

---

## Instalação e Deploy

### 1. Clone o repositório e autentique na org

```bash
git clone https://github.com/MarcTCruz/weather-dashboard-sf.git
cd WeatherChallenge

# Autentique e defina o alias da org destino
sf org login web --alias minha-org --instance-url https://login.salesforce.com
```

### 2. Deploy completo

```bash
sf project deploy start \
  --source-dir force-app \
  --target-org minha-org \
  --test-level RunSpecifiedTests \
  --tests WeatherServiceTest \
  --wait 10
```

O deploy inclui automaticamente:

- Custom Metadata Type `WeatherAPIConfig__mdt` e seus campos
- Registro de configuração padrão `WeatherAPIConfig.Default`
- Remote Site Settings para ambos os domínios Open-Meteo
- Classes Apex: `WeatherDTO`, `WeatherService`, `WeatherServiceTest`
- LWC: `weatherDashboard`
- Custom Tab `Painel_Climatico` (apontando diretamente para o LWC via `<lwcComponent>`)
- Lightning App `Painel Climático` (disponível no App Launcher)
- Permission Set `WeatherDashboardUser` (visibilidade da aba + acesso ao Apex)
- Named Credentials `OpenMeteo_Forecast` e `OpenMeteo_Geocoding` (NoAuthentication)

### 3. Atribuir o Permission Set ao usuário

```bash
sf org assign permset \
  --name WeatherDashboardUser \
  --target-org minha-org
```

### 4. Acessar o Painel Climático

Há **três formas** de visualizar o componente após o deploy:

| Forma | Como |
|---|---|
| **App Launcher** | Clique no App Launcher → busque "Painel Climático" → clique no app. |
| **URL direta** | Navegue para `/lightning/cmp/c__weatherDashboard` (target `lightning__UrlAddressable`). |
| **App Builder** | Abra o **Lightning App Builder**, arraste o componente "Painel Climático" para qualquer App/Home/Record Page. |

### 5. Executar os testes isoladamente (opcional)

```bash
sf apex run test \
  --class-names WeatherServiceTest \
  --target-org minha-org \
  --result-format human \
  --wait 5
```

Cobertura esperada: **≥ 85%** em `WeatherService.cls`.

---

## Endpoints Consumidos

### Geocoding API

| Propriedade | Valor |
|---|---|
| URL base | `callout:OpenMeteo_Geocoding/v1/search` (resolvido via Named Credential para `https://geocoding-api.open-meteo.com/v1/search`) |
| Método | GET |
| Named Credential | `OpenMeteo_Geocoding` (NoAuthentication / Anonymous) |
| Remote Site | `OpenMeteoGeocoding` (mantido como fallback) |

**Parâmetros enviados:**

| Parâmetro | Exemplo | Descrição |
|---|---|---|
| `name` | `São Paulo` | Nome da cidade pesquisada |
| `count` | `1` | Retorna apenas o primeiro resultado |
| `language` | `en` | Idioma dos nomes retornados |
| `format` | `json` | Formato da resposta |

**Campos utilizados da resposta:**

`name`, `latitude`, `longitude`, `country`, `country_code`, `timezone`, `admin1`

---

### Forecast API

| Propriedade | Valor |
|---|---|
| URL base | `callout:OpenMeteo_Forecast/v1/forecast` (resolvido via Named Credential para `https://api.open-meteo.com/v1/forecast`) |
| Método | GET |
| Named Credential | `OpenMeteo_Forecast` (NoAuthentication / Anonymous) |
| Remote Site | `OpenMeteoForecast` (mantido como fallback) |

**Parâmetros enviados:**

| Parâmetro | Exemplo | Descrição |
|---|---|---|
| `latitude` | `-23.5505` | Latitude obtida do Geocoding |
| `longitude` | `-46.6333` | Longitude obtida do Geocoding |
| `current` | *(ver abaixo)* | Variáveis meteorológicas solicitadas |
| `timezone` | `America/Sao_Paulo` | Fuso horário para `time` na resposta |

**Variáveis `current` solicitadas** (configurável via `WeatherAPIConfig__mdt.ForecastCurrentParams__c`):

| Variável | Unidade padrão | Descrição |
|---|---|---|
| `temperature_2m` | °C | Temperatura a 2 m de altitude |
| `apparent_temperature` | °C | Sensação térmica |
| `relative_humidity_2m` | % | Umidade relativa |
| `wind_speed_10m` | km/h | Velocidade do vento a 10 m |
| `precipitation` | mm | Precipitação atual |
| `weather_code` | WMO | Código de condição meteorológica (WMO 4677) |

---

## Decisões Técnicas

### Custom Metadata Type para configuração

Todos os endpoints e parâmetros de API são lidos de `WeatherAPIConfig__mdt` em runtime. Isso garante que:

- **Nenhuma URL é hardcoded** no código Apex.
- A configuração pode ser alterada via deploy de metadados, sem alterar classes Apex.
- Os testes injetam um registro sintético via `WeatherService.testConfig`, eliminando dependência de CMDT na org de teste.

### Separação de responsabilidades (DTO + Service)

- `WeatherDTO.cls` — contém exclusivamente estruturas de dados (inner classes). Sem lógica.
- `WeatherService.cls` — toda a lógica de negócio, orquestração de chamadas e mapeamento de resultados.

Essa separação facilita a evolução independente do contrato de dados e da lógica de integração.

### `@AuraEnabled` imperativo (sem `@wire`)

A busca é acionada explicitamente pelo usuário (clique no botão ou tecla Enter). Não há valor em reatividade automática via `@wire` — o padrão imperativo com `async/await` é mais adequado e oferece controle total sobre estados de loading e erro.

### WMO Weather Code → Descrição + Emoji

O campo `weather_code` da API segue o padrão **WMO 4677**. `WeatherService` mapeia todos os códigos (0–99) para descrição textual em inglês e um emoji correspondente. Isso é feito internamente, sem dependência de biblioteca externa, mantendo o deploy simples.

### HttpCalloutMock multi-resposta para testes

Como cada busca realiza **duas** chamadas HTTP sequenciais (geocoding → forecast), o `WeatherServiceTest` implementa `MultiMock` — uma fila de `HttpResponse` consumida em ordem. Isso evita mock único que não distingue qual chamada está sendo testada.

### Named Credentials para chamadas externas

Os endpoints Open-Meteo são acessados via **Named Credentials** (`OpenMeteo_Forecast` e `OpenMeteo_Geocoding`), com protocolo `NoAuthentication` (a API é pública). O Custom Metadata armazena o endpoint no formato `callout:<NamedCredential>/<path>`, e o Salesforce roteia a requisição automaticamente. Vantagens sobre URL direta + Remote Site Setting:

- Endpoint físico fica em **um único lugar** (a Named Credential), não disperso em múltiplas configurações.
- Suporte nativo a futura troca de protocolo (BasicAuth, OAuth) sem alterar código Apex.
- Permite atribuição via Permission Set, alinhando ao padrão moderno do Salesforce.

### Remote Site Settings mantidos como fallback

Os dois Remote Site Settings (`OpenMeteoForecast`, `OpenMeteoGeocoding`) permanecem no projeto como fallback caso o Custom Metadata seja revertido para URLs diretas em algum cenário de troubleshooting.

---

## Interface

> _Adicionar prints/GIF após deploy em org._

**Estado inicial (vazio):**

```
┌─────────────────────────────────────────────┐
│  Weather Dashboard               ☀           │
│  ┌──────────────────────┐  [Search]          │
│  │ City                 │                    │
│  └──────────────────────┘                    │
│                                              │
│              🌍                               │
│     Search for a city to see its weather     │
│    Powered by Open-Meteo — free, no API key  │
└─────────────────────────────────────────────┘
```

**Resultado para "São Paulo":**

```
┌─────────────────────────────────────────────┐
│  Weather Dashboard               ☀           │
│  ┌──────────────────────┐  [Search]          │
│  │ São Paulo            │                    │
│  └──────────────────────┘                    │
│                                              │
│              ⛅                               │
│         São Paulo, BR                        │
│  America/Sao_Paulo • Sat May 10, 14:30       │
│         Partly Cloudy                        │
│                                              │
│  🌡️          🤔          💧         💨   🌧️   │
│ TEMPERATURE FEELS LIKE HUMIDITY  WIND  PREC  │
│   22.4°C     20.1°C     68%    14.5 km/h 0mm│
└─────────────────────────────────────────────┘
```

---

## Estrutura do Projeto

```
WeatherChallenge/
├── force-app/main/default/
│   ├── applications/
│   │   └── Painel_Climatico.app-meta.xml          # Lightning App (App Launcher)
│   ├── classes/
│   │   ├── WeatherDTO.cls                         # DTOs: GeocodingResponse, ForecastResponse, WeatherResult
│   │   ├── WeatherService.cls                     # Lógica: geocodeCity, getWeatherByCity, mapeamento WMO (pt-BR)
│   │   └── WeatherServiceTest.cls                 # Testes unitários (≥85% cobertura)
│   ├── customMetadata/
│   │   └── WeatherAPIConfig.Default.md-meta.xml   # Registro CMT com URLs e params padrão
│   ├── lwc/
│   │   └── weatherDashboard/
│   │       ├── weatherDashboard.html              # Template em pt-BR: busca, loading, erro, resultado, estado vazio
│   │       ├── weatherDashboard.js                # Controller: estados, handlers, getter formattedTime
│   │       ├── weatherDashboard.css               # Estilos: metric-card hover, temp-value brand color
│   │       └── weatherDashboard.js-meta.xml       # Targets: AppPage, HomePage, RecordPage, Tab, UrlAddressable
│   ├── objects/WeatherAPIConfig__mdt/             # CMT schema: 4 campos (endpoints, params, timeout)
│   ├── permissionsets/
│   │   └── WeatherDashboardUser.permissionset-meta.xml  # Acesso ao Apex + visibilidade da aba
│   ├── remoteSiteSettings/
│   │   ├── OpenMeteoForecast.remoteSite-meta.xml
│   │   └── OpenMeteoGeocoding.remoteSite-meta.xml
│   └── tabs/
│       └── Painel_Climatico.tab-meta.xml          # Custom Tab apontando para o LWC weatherDashboard
└── sfdx-project.json
```

---

## Referências

- [Open-Meteo Geocoding API](https://open-meteo.com/en/docs/geocoding-api)
- [Open-Meteo Forecast API](https://open-meteo.com/en/docs)
- [WMO Weather Interpretation Codes](https://open-meteo.com/en/docs#weathervariables)
- [Salesforce LWC Dev Guide](https://developer.salesforce.com/docs/component-library/documentation/en/lwc)
- [Apex HttpCalloutMock](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_restful_http_testing_httpcalloutmock.htm)
