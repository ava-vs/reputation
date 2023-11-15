import Hub "./Hub";
import API "./API";

actor Main {
    let hub = Hub.Hub();
    let api = API.API(hub);

}
