<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=realm.password && realm.registrationAllowed && !registrationDisabled; section>
    <#if section = "header">
        Log In
    <#elseif section = "form">
    
    <div id="kc-form" class="w-full">
      
      <!-- Glassmorphism Card -->
      <div id="kc-form-wrapper" class="bg-white/5 backdrop-blur-xl border border-glassborder p-8 rounded-3xl shadow-[0_8px_32px_0_rgba(0,0,0,0.37)]">
        
        <!-- Headers -->
        <div class="text-center mb-8">
            <h1 class="text-2xl font-bold text-white tracking-tight mb-1">Alma Mater Studiorum</h1>
            <h2 class="text-lg font-light text-gray-400">Dipartimento BiGeA</h2>
        </div>

        <form id="kc-form-login" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post" class="space-y-6">
            
            <!-- Username Input -->
            <div class="space-y-1 relative">
                <label for="username" class="block text-sm font-medium text-gray-300"><#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if></label>
                <div class="relative">
                    <input tabindex="1" id="username" name="username" value="${(login.username!'')}" type="text" autofocus autocomplete="off" 
                        class="block w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-unibored focus:border-transparent transition-all hover:bg-white/10" 
                        placeholder="nome.cognome@studio.unibo.it" />
                </div>
            </div>

            <!-- Password Input -->
            <div class="space-y-1 relative">
                <label for="password" class="block text-sm font-medium text-gray-300">Password</label>
                <div class="relative">
                    <input tabindex="2" id="password" name="password" type="password" autocomplete="off" 
                        class="block w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-unibored focus:border-transparent transition-all hover:bg-white/10" 
                        placeholder="••••••••" />
                </div>
            </div>

            <div class="flex items-center justify-between pt-2">
                <#if realm.rememberMe && !usernameHidden??>
                    <div class="flex items-center group cursor-pointer">
                        <div class="relative flex items-start">
                            <div class="flex items-center h-5">
                                <input tabindex="3" id="rememberMe" name="rememberMe" type="checkbox" 
                                    class="h-4 w-4 bg-transparent border-gray-500 rounded text-unibored focus:ring-unibored focus:ring-offset-gray-900 transition-colors cursor-pointer" 
                                    <#if login.rememberMe??>checked</#if> />
                            </div>
                            <div class="ml-2 text-sm">
                                <label for="rememberMe" class="font-medium text-gray-400 group-hover:text-gray-200 transition-colors cursor-pointer">${msg("rememberMe")}</label>
                            </div>
                        </div>
                    </div>
                </#if>
                
                <#if realm.resetPasswordAllowed>
                    <div class="text-sm">
                        <a tabindex="5" href="${url.loginResetCredentialsUrl}" class="font-medium text-unibored hover:text-red-400 transition-colors">Dimenticato la password?</a>
                    </div>
                </#if>
            </div>

            <!-- Submit Button -->
            <div id="kc-form-buttons" class="pt-4">
                <button tabindex="4" name="login" id="kc-login" type="submit" 
                    class="w-full flex justify-center py-3.5 px-4 border border-transparent rounded-xl shadow-lg text-sm font-bold text-white bg-unibored hover:bg-[#a00b0c] focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-unibored focus:ring-offset-gray-900 transition-all active:scale-[0.98]">
                    Accedi ai Servizi
                </button>
            </div>

        </form>
      </div>
    </div>
    
    <#elseif section = "info" >
        <#if realm.password && realm.registrationAllowed && !registrationDisabled>
            <div id="kc-registration" class="mt-6 text-center text-sm text-gray-400">
                <span>Non hai un account? <a tabindex="6" href="${url.registrationUrl}" class="font-medium text-unibored hover:text-red-400 transition-colors">Registrati ora</a></span>
            </div>
        </#if>
    </#if>
</@layout.registrationLayout>
