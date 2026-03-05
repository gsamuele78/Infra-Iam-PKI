<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html lang="${properties.kcHtmlClass!}" class="h-full">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${msg("loginTitle",(realm.displayName!'ALMA MATER STUDIORUM - UNIVERSITÀ DI BOLOGNA'))}</title>
    <!-- Tailwind CSS (via CDN for simplicity and isolation) -->
    <script src="https://cdn.tailwindcss.com"></script>
    <!-- Inter Font -->
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        body { font-family: 'Inter', sans-serif; }
    </style>
    <!-- Tailwind Config injected in head to apply Unibo BIgEA Colors -->
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        unibored: '#C80E0F',
                        bigeagray: '#2C3E50',
                        glassborder: 'rgba(255, 255, 255, 0.2)'
                    }
                }
            }
        }
    </script>
</head>
<body class="h-full flex flex-col items-center justify-center bg-gradient-to-br from-gray-900 via-stone-900 to-black min-h-screen text-gray-200">
    
    <!-- Decorative background elements for premium feel (Unibo colors) -->
    <div class="fixed top-0 left-0 w-full h-full overflow-hidden z-0 pointer-events-none">
        <div class="absolute -top-40 -left-40 w-[40rem] h-[40rem] bg-unibored rounded-full mix-blend-screen filter blur-[120px] opacity-10"></div>
        <div class="absolute top-40 -right-20 w-[30rem] h-[30rem] bg-red-900 rounded-full mix-blend-screen filter blur-[100px] opacity-20"></div>
    </div>

    <div class="w-full max-w-md mx-auto z-10 relative px-4">
        
        <!-- Alerts Context (Keycloak standard messaging) -->
        <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
            <div class="mb-6 p-4 rounded-xl shadow-lg border backdrop-blur-md 
                        ${ (message.type = 'success')?string('bg-green-500/10 border-green-500/30 text-green-300',
                       (message.type = 'warning')?string('bg-orange-500/10 border-orange-500/30 text-orange-300',
                       (message.type = 'error')?string('bg-red-500/10 border-red-500/40 text-red-300',
                       'bg-blue-500/10 border-blue-500/30 text-blue-300'))) }">
                <span class="text-sm font-medium">${kcSanitize(message.summary)?no_esc}</span>
            </div>
        </#if>

        <!-- Main Form Injection -->
        <#nested "form">
        
    </div>
    
    <!-- Footer aligned with Unibo / BiGeA styling -->
    <div class="fixed bottom-6 text-center z-10 w-full opacity-60 text-xs">
        <p>&copy; ALMA MATER STUDIORUM - Università di Bologna</p>
        <p>BiGeA Department Services</p>
    </div>
</body>
</html>
</#macro>
