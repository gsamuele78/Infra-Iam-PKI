<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html lang="${properties.kcHtmlClass!}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${msg("loginTitle",(realm.displayName!'ALMA MATER STUDIORUM - UNIVERSITÀ DI BOLOGNA'))}</title>
    <!-- Local CSS without external CDNs for true Airgap / Zero-Trust -->
    <link rel="stylesheet" href="${url.resourcesPath}/css/styles.css">
</head>
<body>
    <div class="background-overlay"></div>
    <div class="main-container">
        <!-- R-studioConf matching Header -->
        <header class="glass-header">
            <div class="logo-container">
                <img src="${url.resourcesPath}/img/left.png" alt="Left Logo" class="logo">
                <div class="site-title">
                    <h1>BIOME BigData Resources</h1>
                    <p class="subtitle">Central Authentication Service</p>
                </div>
                <img src="${url.resourcesPath}/img/right.png" alt="Right Logo" class="logo">
            </div>
        </header>

        <!-- Alerts Context (Keycloak standard messaging) -->
        <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
            <div class="alert-${message.type}">
                <span class="text-sm font-medium">${kcSanitize(message.summary)?no_esc}</span>
            </div>
        </#if>

        <!-- Main Form Injection -->
        <#nested "form">
        
        <!-- Footer aligned with Unibo / BiGeA styling -->
        <footer class="glass-footer">
            <p>&copy; ALMA MATER STUDIORUM - Università di Bologna</p>
            <p>BiGeA Department Services</p>
        </footer>
    </div>
</body>
</html>
</#macro>
