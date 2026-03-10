<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=realm.password && realm.registrationAllowed && !registrationDisabled; section>
    <#if section = "header">
        Log In
    <#elseif section = "form">
    
    <div id="kc-form" class="login-modal-content">
        <!-- Headers -->
        <div class="login-form">
            <h2>Secure Connect</h2>

            <form id="kc-form-login" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post">
                
                <!-- Username Input -->
                <div class="form-group">
                    <label for="username"><#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if></label>
                    <input tabindex="1" id="username" name="username" value="${(login.username!'')}" type="text" autofocus autocomplete="username" placeholder="nome.cognome@studio.unibo.it" />
                </div>

                <!-- Password Input -->
                <div class="form-group">
                    <label for="password">Password</label>
                    <input tabindex="2" id="password" name="password" type="password" autocomplete="current-password" placeholder="••••••••" />
                </div>

                <div style="display: flex; justify-content: space-between; font-size: 0.9rem; margin-bottom: 1rem;">
                    <#if realm.rememberMe && !usernameHidden??>
                        <div>
                            <input tabindex="3" id="rememberMe" name="rememberMe" type="checkbox" <#if login.rememberMe??>checked</#if> />
                            <label for="rememberMe" style="color: var(--sage-green); margin-left: 0.2rem;">${msg("rememberMe")}</label>
                        </div>
                    </#if>
                    
                    <#if realm.resetPasswordAllowed>
                        <div>
                            <a tabindex="5" href="${url.loginResetCredentialsUrl}" style="color: var(--unibo-red); text-decoration: none;">Dimenticato la password?</a>
                        </div>
                    </#if>
                </div>

                <!-- Submit Button -->
                <div id="kc-form-buttons">
                    <button tabindex="4" name="login" id="kc-login" type="submit" class="submit-btn">
                        Accedi ai Servizi
                    </button>
                </div>

            </form>
        </div>
    </div>
    
    <#elseif section = "info" >
        <#if realm.password && realm.registrationAllowed && !registrationDisabled>
            <div id="kc-registration" style="text-align: center; margin-top: 1rem; font-size: 0.9rem; color: #ccc;">
                <span>Non hai un account? <a tabindex="6" href="${url.registrationUrl}" style="color: var(--unibo-red);">Registrati ora</a></span>
            </div>
        </#if>
    </#if>
</@layout.registrationLayout>
