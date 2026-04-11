import com.pi4j.plugin.ffm.common.file.FileDescriptorNative;
import com.pi4j.plugin.ffm.common.ioctl.IoctlNative;
import com.pi4j.plugin.ffm.common.poll.PollNative;
import com.pi4j.plugin.ffm.common.permission.PermissionNative;
import com.pi4j.plugin.ffm.common.i2c.SMBusNative;

public class Probe {
    public static void main(String[] args) {
        new FileDescriptorNative();   // triggers FileDescriptorContext static init
        new IoctlNative();            // triggers IoctlContext static init
        new PollNative();             // triggers PollContext static init
        new PermissionNative();       // triggers PermissionContext static init
        new SMBusNative();            // triggers SMBusContext static init (requires libi2c)
    }
}
