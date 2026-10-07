# TUTORIAL

## 0. Förutsättningar

- .NET 10 SDK
- Azure CLI (az), inloggad mot rätt prenumeration
- Git och GitHub CLI (gh), inloggad
- Bicep CLI (`az bicep install`)
- Git Bash (Windows) - scripten i repot är bash, inte PowerShell
- Docker (valfritt - imagen går att bygga helt i Azure med `az acr build` utan lokal Docker)

Namn som används genomgående:

- Resursgrupp: `rg-clo25-hanita-sc`
- App Service: `app-clo25-hanita`, plan `asp-clo25-hanita-sc`
- Container registry: `acrclo25hanita`
- Container Apps-miljö: `cae-clo25-hanita`, app `ca-clo25-hanita`
- Key Vault: `kv-clo25-hanita`
- Region: `swedencentral` (se avvikelse under punkt 9)

## 1. Hämta och kör projektet lokalt

Innan något rör Azure: klona repot och verifiera att appen bygger och testerna går igenom på egen hand.

```bash
git clone https://github.com/95hanmel-coder/Skalbaramolnappz
cd Skalbaramolnappz

dotnet build
dotnet test
```

Valfritt, för att se appen svara lokalt innan något deployas:

```bash
dotnet run --project src/Beacon.Api
# i ett andra terminalfönster:
curl http://localhost:5001/health
```

Förväntat: `dotnet test` visar två godkända tester, och `curl` svarar `OK`.

## 2. Översikt och arkitektur

Appen heter Beacon och är ett minimalt .NET 10-API med två endpoints: `/` som returnerar lite JSON, och `/health` som alltid svarar 200 OK. Appen gör ingenting mer än så med flit - det är infrastrukturen runt den som är uppgiften, inte applikationslogiken.

Samma kod körs på två helt separata sätt i Azure:

```
                  ┌─────────────────────┐
                  │   GitHub repo        │
                  │   (källkod, Bicep,   │
                  │   scripts, pipelines)│
                  └──────────┬───────────┘
                             │
           ┌─────────────────┴─────────────────┐
           ▼                                     ▼
  ┌─────────────────────┐          ┌──────────────────────────┐
  │   Webbappspåret       │          │   Containerspåret         │
  │                       │          │                            │
  │  App Service Plan B1  │          │  Container Registry (ACR) │
  │  (3 instanser)        │          │  Container Apps-miljö     │
  │  └─ Beacon.Api (.dll) │          │  └─ Container App         │
  │                       │          │     (1-5 repliker)        │
  └─────────────────────┘          └──────────────────────────┘
           │                                     │
           └──────────────┬──────────────────────┘
                           ▼
                 Key Vault (kv-clo25-hanita)
                 - en hemlighet, läst av webbappen
                 via managed identity
```

Webbappspåret deployas via `scripts/deploy-infra.sh` och en GitHub Actions-pipeline (`deploy.yml`) som bygger, testar och skickar upp koden med en publish profile. Containerspåret deployas via `scripts/deploy-container.sh` för infrastrukturen, och en egen pipeline (`deploy-container.yml`) som bygger imagen, pushar den till registret, och sedan rullar ut den nya imagen till Container Apps - helt automatiskt vid varje push.

## 3. Vilka Azure-tjänster jag valde och varför (K1)

- **App Service (Linux, B1)** för webbappspåret. En vanlig PaaS-tjänst för webbappar, med inbyggd lastbalansering mellan instanser och en inbyggd health check-mekanism som tar trasiga instanser ur trafik. B1 är den billigaste nivån som stödjer flera instanser (se kostnadsresonemang under punkt 6).
- **Azure Container Registry (Basic)** för att lagra Docker-imagen. Basic räcker gott för en kurs där en enda person bygger och pushar images.
- **Azure Container Apps** för containerspåret, i stället för AKS. Container Apps ger skalning (min/max repliker, en HTTP-baserad skalningsregel) utan att jag behöver hantera ett helt Kubernetes-kluster - rätt nivå av komplexitet för den här appens behov.
- **Azure Key Vault** för att hålla en hemlighet utanför kod och Git. Appen läser den via sin managed identity, utan att något lösenord förekommer någonstans i kedjan.
- **GitHub Actions** för CI/CD, kopplat till både App Service och Container Apps.

## 4. Webbappspåret: steg för steg (F2)

Från ett tomt repo och en tom resursgrupp:

```bash
# 1. Bygg upp hela infrastrukturen (skapar resursgruppen om den saknas)
./scripts/deploy-infra.sh rg-clo25-hanita-sc

# 2. Starta pipelinen manuellt, eller pusha en ändring till main
gh workflow run deploy.yml

# 3. Verifiera
./scripts/health-check.sh https://app-clo25-hanita.azurewebsites.net/health
```

`deploy-infra.sh` kör `az deployment group create` mot `infra/main.bicep` och `infra/main.bicepparam`, och avslutar med att kontrollera att CI/CD-identiteten (se punkt 8) har rätt roll på resursgruppen - en roll som annars försvinner varje gång resursgruppen rivs.

Pipelinen (`deploy.yml`) har två jobb: `build` (checkout, `dotnet build`, `dotnet test`, `dotnet publish`, ladda upp artefakten) och `deploy` (ladda ner artefakten, `azure/webapps-deploy` med en publish profile, och till sist ett hälsokontroll-steg som kör `scripts/health-check.sh` mot den driftsatta appen).

## 5. Containerspåret: steg för steg (F1)

```bash
# 1. Bygg upp registret och webbappsspåret, om det inte redan finns
./scripts/deploy-infra.sh rg-clo25-hanita-sc

# 2. Skapa registret och bygg första imagen (hönan-och-ägget-lösning:
#    Container App-mallen behöver en image som redan finns i registret)
az acr create --resource-group rg-clo25-hanita-sc --name acrclo25hanita --sku Basic --admin-enabled true
az acr build --registry acrclo25hanita --image beacon:v1 --file src/Beacon.Api/Dockerfile .

# 3. Deploya Container Apps-miljön och appen
./scripts/deploy-container.sh rg-clo25-hanita-sc

# 4. Verifiera
TARGET_URL="https://$(az containerapp show --resource-group rg-clo25-hanita-sc \
  --name ca-clo25-hanita --query properties.configuration.ingress.fqdn --output tsv)/health"
./scripts/health-check.sh "$TARGET_URL"
```

Hela kedjan går också att köra i ett enda kommando med `scripts/provision-all.sh rg-clo25-hanita-sc acrclo25hanita`, som kedjar ihop alla stegen ovan i rätt ordning.

Pipelinen (`deploy-container.yml`) har två jobb. `build-and-push` bygger imagen med Docker direkt på GitHub-runnern (inte `az acr build`, eftersom det jobbet bara har ett registerlösenord, ingen Azure-identitet), taggar den med både commit-hashen och `latest`, och pushar båda till registret. `deploy` loggar in mot Azure med OIDC (se punkt 8) och rullar själv ut den nya imagen:

```bash
az containerapp update --name ca-clo25-hanita --resource-group rg-clo25-hanita-sc \
  --image acrclo25hanita.azurecr.io/beacon:<commit-hash>
```

följt av ett hälsokontroll-steg mot den nya revisionen. Hela kedjan - bygg, pusha, rulla ut, verifiera - sker alltså automatiskt vid en push till `main`.

## 6. Kostnadseffektivitet

Tjänstevalen är gjorda med kostnad i åtanke, inte bara funktion:

- **App Service B1** är den billigaste nivån som stödjer flera instanser samtidigt (nivån under, F1/Free, tillåter bara en instans). Att köra tre instanser på B1 ger tre gånger plankostnaden - ett medvetet val mellan att visa redundans konkret och hålla kostnaden nere, i stället för att välja en dyrare nivå med funktioner (till exempel inbyggd autoscale) som inte behövs för den här uppgiften.
- **ACR Basic** är den billigaste registernivån, med lägre lagringskvot och färre funktioner (bland annat ingen geo-replikering) än Standard/Premium - gott nog för en enda utvecklares images under en kurs.
- **Container Apps skalning** är satt till `minReplicas: 1`, så minst en replik kör och kostar alltid, och `maxReplicas: 5` sätter ett tak så att en trafikspik inte kan skala obegränsat och dra iväg i kostnad. Till skillnad från App Service-planens fasta kostnad per instans betalar man här närmare faktisk förbrukning per replik.

## 7. Skalning och lastbalansering i båda spåren (K2)

**Webbappspåret:** App Service-planen är satt till 3 instanser (`sku.capacity: 3` i `infra/main.bicep`). App Service fördelar trafiken mellan dem automatiskt, och en health check på `/health` tar en trasig instans ur trafik.

**Containerspåret:** Container App-mallen har `minReplicas: 1`, `maxReplicas: 5` och en skalningsregel baserad på samtidiga HTTP-anrop (`concurrentRequests: 20` per replik). Standardvärdena behölls eftersom appen inte har någon verklig trafik att dimensionera efter - skulle den få det är det här raden jag skulle justera först.

**Tillstånd (state):** Appen är medvetet stateless - ingen databas, ingen fillagring. Det är därför skalning till flera instanser respektive repliker fungerar problemfritt: varje instans är utbytbar och vet inget om de andra. Hade appen sparat data i en fil på disk hade det fungerat lokalt men inte i molnet - skalar man ut till flera repliker får man flera separata, okopplade kopior av datan i stället för en delad sanning.

Om appen i framtiden behövde spara data skulle valet stå mellan en relationsdatabas (till exempel Azure SQL Database) för strukturerad data med transaktionskrav, eller en NoSQL-lösning (till exempel Cosmos DB) för enklare data som behöver skala horisontellt utan ett fast schema. En delad cache (till exempel Azure Managed Redis) blir relevant först när flera repliker behöver komma åt samma korta, snabbåtkomliga data - till exempel sessionsdata eller resultatet av en dyr beräkning - utan att varje replik räknar om det själv. Utan en delad cache uppstår samma problem som med lokal fillagring: varje replik har sin egen, okopplade kopia.

**Grundsäkerhet i båda:** `httpsOnly: true` och `minTlsVersion: '1.3'` på webbappen, `allowInsecure: false` på containerappens ingress. Ingen hårdkodad hemlighet i koden.

## 8. CI/CD och driftsättningsstrategi (K4)

**Webbappspåret** använder en enkel **in-place-driftsättning**: det nya paketet skrivs över den befintliga appen, som sedan startas om. Det är varken rolling, blue-green eller canary - alla tre kräver trafikstyrning mellan flera versioner samtidigt, vilket den här lösningen inte har. En positiv bieffekt jag lade märke till: App Service håller den gamla versionen igång tills den nya svarar, så jag upplevde aldrig ett synligt avbrott vid en driftsättning - men det är en bieffekt av plattformen, inte en strategi jag valt eller kan styra.

**Containerspåret** får en helt annan strategi, utan att jag konfigurerat något extra för det: varje `az containerapp update` skapar en ny **revision**. Jag såg detta konkret i min miljö:

```
Rev                       Active
------------------------  --------
ca-clo25-hanita--00lmxl6  False
ca-clo25-hanita--0000001  True
```

Den gamla revisionen försvinner inte - den blir bara inaktiv, och historiken finns kvar. All trafik går automatiskt till den senaste revisionen eftersom jag inte satt `activeRevisionsMode` till `Multiple` med en trafikdelning. Det här är närmast en enkel ersättning utan riktig trafikdelning, inget valbart växlingsögonblick och ingen inbyggd rollback-mekanism - återigen plattformens standardbeteende snarare än en vald strategi.

## 9. Säkerhetsdesign (VG, F2)

**Hemligheter:** Appen har en systemtilldelad managed identity (`identity: { type: 'SystemAssigned' }` i Bicep-mallen). Ett Key Vault (`kv-clo25-hanita`) innehåller en hemlighet, och appens identitet har en access policy som bara ger `get` och `list` - alltså läsrätt, aldrig skrivrätt. Jag själv har dessutom `set`, så jag kan uppdatera hemligheten från terminalen. Det här är konkret least privilege: två identiteter, olika rättigheter, verifierat direkt mot resursen:

```json
[
  { "id": "<app-principal-id>", "secrets": ["get", "list"] },
  { "id": "<mitt-eget-id>",     "secrets": ["get", "list", "set"] }
]
```

Appen läser hemligheten via en app-inställning som pekar på en Key Vault-referens, inte värdet självt:

```
MY_SECRET = @Microsoft.KeyVault(SecretUri=https://kv-clo25-hanita.vault.azure.net/secrets/demo-secret)
```

App Service löser upp referensen vid körning med appens egen identitet - verifierat med Azures `configreferences`-API som rapporterade status `Resolved`. Räknar man igenom hela kedjan finns inget lösenord i koden, i Bicep-filen, i GitHub secrets, i app-inställningen eller i min terminalhistorik. Hemligheten sattes interaktivt med `read -rs`, som döljer inmatningen, i stället för `export VAR=värde` som hade lämnat kvar den i terminalhistoriken.

**Behörighetsmodell:** Key Vault är satt till access policies (`enableRbacAuthorization: false`) i stället för RBAC. Det var ett medvetet val: access policies kräver bara Contributor-rollen på resursgruppen, medan RBAC hade krävt rätt att dela ut roller. Jag testade senare om jag faktiskt hade rätt att dela ut roller och upptäckte att jag har det - så RBAC är ett alternativ jag skulle kunna byta till, men valde bort för den här labben eftersom access policies redan löste behovet med mindre arbete.

**Pipelinens autentisering:** Jag byggde och verifierade en fullständig OIDC-identitet för pipelinen: en app-registrering, en Contributor-roll på resursgruppen, en federerad credential bunden till exakt detta repo och `main`-grenen, och motsvarande GitHub-variabler (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`). Den identiteten används nu av containerpipelinens `deploy`-jobb, som loggar in mot Azure utan något sparat lösenord och sedan kör `az containerapp update`. Webbappspipelinen använder fortfarande en publish profile för själva kodleveransen, eftersom `azure/webapps-deploy` autentiserar separat från vanliga Azure CLI-anrop - men den delar samma Contributor-roll för sitt `infra`-steg.

Två hemligheter återstår i lösningen: registrets admin-lösenord (`ACR_PASSWORD`), som containerpipelinens `build-and-push`-jobb använder för att pusha imagen, och webbappens publish profile. Båda skulle kunna ersättas helt av OIDC-baserad autentisering - nästa steg vore att logga in mot registret med samma OIDC-identitet i stället för ett lagrat lösenord, och att undersöka om `azure/webapps-deploy` kan autentisera via OIDC i en nyare version.

**Transportsäkerhet:** `httpsOnly: true` och `minTlsVersion: '1.3'` i App Service-mallen tvingar fram HTTPS och stänger ute äldre, svagare TLS-versioner. `allowInsecure: false` gör samma sak för containerspårets ingress.

## 10. Alternativ jag övervägde (VG, K1 / Komp1 / Komp2)

- **Bicep mot Terraform mot att klicka i Portalen.** Jag valde Bicep eftersom det är inbyggt i Azure CLI utan extra verktyg, och det integreras naturligt med `what-if` för att se exakt vad en ändring kommer göra innan den körs. Terraform hade gett samma resultat men med ett extra verktyg att installera och hålla reda på.
- **Access policies mot RBAC för Key Vault.** Beskrivet i punkt 9 - access policies krävde mindre behörighet att sätta upp, trots att RBAC är det Microsoft rekommenderar idag.
- **Container Apps mot AKS.** Container Apps gav mig skalning och containerdrift utan att behöva hantera ett helt Kubernetes-kluster, vilket är en rimligare nivå av komplexitet för en app av den här storleken.
- **Region: westeurope mot swedencentral.** Under en av labbarna gav `az appservice plan create` i westeurope upprepade `429 throttled`-fel, oavsett vilken SKU jag testade. Jag felsökte genom att testa flera SKU:er och en annan region (swedencentral), som fungerade direkt. Beslutet blev att hålla fast vid swedencentral konsekvent genom hela projektet i stället för att blanda regioner mellan labbarna.
- **Serverless (Azure Functions) mot alltid-på-instanser.** Jag övervägde Functions men valde bort det eftersom appen är ett kontinuerligt svarande webb-API utan händelsedriven arbetslast (köer, schemalagda jobb) - det är inte den typen av arbete Functions är byggt för.

## 11. Kända svagheter och hur jag skulle åtgärda dem (VG, Komp2)

- **`MY_SECRET` sattes med CLI, inte i Bicep-mallen.** En app som byggs upp helt på nytt från `main.bicep` ensam har inga app-inställningar alls - jag hade då behövt sätta referensen till Key Vault manuellt igen. Skälet till att jag inte löste det i mallen är att en Bicep-resurs som deklarerar `appSettings` ersätter _alla_ befintliga inställningar, inklusive `SCM_DO_BUILD_DURING_DEPLOYMENT` som redan sätts separat - att hantera båda i samma mall kändes som en för stor risk att införa ett nytt fel så nära deadline. Nästa steg vore att samla alla app-inställningar, inklusive Key Vault-referensen, i mallen på en gång.
- **Key Vault byggs inte om av `provision-all.sh`.** Ett Key Vault som raderas hamnar i ett "soft delete"-läge i sju dagar innan namnet blir ledigt igen, vilket gör det olämpligt att inkludera i ett script som ska gå att köra om varje lektionsdag.
- **Image-taggen förekommer på fler än ett ställe.** `container.bicepparam` pekar på `:v1`, medan pipelinen pushar och rullar ut efter commit-hash. Kör jag `deploy-container.sh` efter att pipelinen rullat ut en ny version, rullas appen tillbaka till `:v1`. Jag håller koll på detta manuellt just nu; nästa steg vore att låta Bicep-mallen peka på `:latest` i stället, eller att skilja tydligare på när scriptet respektive pipelinen får ändra imagen.
- **ACR:s admin-lösenord i stället för managed identity + AcrPull**, för själva bygg-och-push-steget i pipelinen (containerappens egen hämtning av imagen använder redan samma lösenord, se punkt 9). En managed identity med rollen AcrPull är ett tydligt nästa steg - jag har inte byggt det, men vet exakt vilka ändringar som krävs.
- **`azure/webapps-deploy` använder fortfarande en publish profile**, inte OIDC, trots att OIDC-identiteten redan finns och används i containerpipelinen. En naturlig förlängning vore att undersöka om kodleveransen till App Service kan göras med samma identitet.

## 12. Rivning / städning

```bash
az group delete --name rg-clo25-hanita-sc --yes --no-wait

# Container Apps-miljön tar lång tid att riva (upp till ~10 min), så
# provisioningState ger bättre information än az group exists under tiden:
az group show --name rg-clo25-hanita-sc --query properties.provisioningState --output tsv
```

Allt som behövs för att bygga upp miljön igen finns i repot: `./scripts/provision-all.sh rg-clo25-hanita-sc acrclo25hanita`.