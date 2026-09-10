import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PoolPacerApp extends Application.AppBase {

    hidden var mView as PoolPacerView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        mView = new PoolPacerView();
        return [mView];
    }

    function onSettingsChanged() as Void {
        if (mView != null) {
            mView.loadSettings();
        }
    }
}
