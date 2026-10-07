import java.io.ByteArrayInputStream;
import java.io.File;
import java.nio.file.Files;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;

import com.tridium.crypto.core.io.CoreCryptoManager;
import com.tridium.crypto.core.io.ICoreTrustStore;
import com.tridium.nre.security.ISecurityInfoProvider;
import com.tridium.nre.security.SecurityInitializer;

/**
 * Headless import of a certificate into the Niagara USER trust store of the user home the
 * invoking NRE security context resolves. No GUI, no keytool, no store password: the NRE
 * security provider owns the key-material passwords.
 *
 * Compile and run it with the Niagara JRE (scripts/import-trust-cert.ps1 does this):
 *   javac -cp "<niagara>/bin/ext/nre.jar;<niagara>/modules/baja.jar" -d out java/TrustImport.java
 *   <niagara>/jre/bin/java -Dniagara.platform.provider=com.tridium.nre.platform.NativePlatformProviderTridium
 *     -Dniagara.security.manager.disable -Dniagara.home=<niagara> -Dniagara.user.home=<userHome>
 *     -cp "<niagara>/bin/ext/nre.jar;<niagara>/modules/baja.jar;<every jar under bin/ext except bcfips>;out"
 *     TrustImport <cert.pem> <alias>
 * Exit 0 = imported or already trusted, 1 = failed, 2 = usage.
 */
public final class TrustImport {
  public static void main(String[] args) throws Exception {
    if (args.length < 2) {
      System.err.println("usage: TrustImport <cert.pem> <alias>");
      System.exit(2);
    }
    File pem = new File(args[0]);
    String alias = args[1];
    if (!pem.isFile()) {
      System.err.println("FATAL: cert file not found: " + pem.getAbsolutePath());
      System.exit(2);
    }
    byte[] der = Files.readAllBytes(pem.toPath());
    CertificateFactory cf = CertificateFactory.getInstance("X.509");
    X509Certificate cert = (X509Certificate) cf.generateCertificate(new ByteArrayInputStream(der));

    ISecurityInfoProvider sec = SecurityInitializer.getInstance().getSecurityInfoProvider();
    System.out.println("securityDir=" + sec.getSecurityDir());
    CoreCryptoManager mgr = CoreCryptoManager.get(sec);
    ICoreTrustStore user = mgr.getUserTrustStore();
    if (user == null) {
      System.err.println("FATAL: no user trust store");
      System.exit(1);
    }
    String existing = user.findCertificate(cert);
    if (existing != null) {
      System.out.println("already-trusted alias=" + existing);
      System.exit(0);
    }
    user.setCertificateEntry(alias, cert);
    user.save();
    X509Certificate back = user.getCertificate(alias);
    System.out.println("imported alias=" + alias + " readback=" + (back != null));
    System.exit(back != null ? 0 : 1);
  }
}
