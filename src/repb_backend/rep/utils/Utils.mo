import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Text "mo:base/Text";
import Time "mo:base/Time";

module {
    // convert date prefix from Int to date

    public func timestampToDate() : Text {
        let seconds = Time.now() / 1_000_000_000;
        let minutes = Int.div(seconds, 60);
        let hours = Int.div(minutes, 60);
        let days = Int.div(hours, 24);

        let secondsInMinute = seconds % 60;
        let minutesInHour = minutes % 60;
        let hoursInDay = hours % 24;

        let years = Int.div(days, 365);
        let year = years + 1970;
        var remainingDays = days - (years * 365);

        let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        var month = 1;
        label l for (i in monthDays.vals()) {
            if (remainingDays < i) break l;
            remainingDays -= i;
            month += 1;
        };

        let day = remainingDays + 1;

        return Int.toText(year) # "-" # Int.toText(month) # "-"
        # Int.toText(day) # " " # Int.toText(hoursInDay) # ":"
        # Int.toText(minutesInHour) # ":" # Int.toText(secondsInMinute);
    };

	public func pushIntoArray<X>(elem : X, array : [X]) : [X] {
		let buffer = Buffer.fromArray<X>(array);
		buffer.add(elem);
		return Buffer.toArray(buffer);
	};

	public func appendArray<X>(array1 : [X], array2 : [X]) : [X] {
		let buffer1 = Buffer.fromArray<X>(array1);
		let buffer2 = Buffer.fromArray<X>(array2);
		buffer1.append(buffer2);
		Buffer.toArray(buffer1);
	};

    // For <SFFNNNGGG> cifer
    public func convertCiferToDottedFormat(cifer : Text) : Text {
        let chars = Text.toArray(cifer);
        let s = Text.fromChar(chars[0]);
        let ff = Text.fromChar(chars[1]) # Text.fromChar(chars[2]);
        let nnn = Text.fromChar(chars[3]) # Text.fromChar(chars[4]) # Text.fromChar(chars[5]);
        let ggg = Text.fromChar(chars[6]) # Text.fromChar(chars[7]) # Text.fromChar(chars[8]);
        return Text.join(".", [s, ff, nnn, ggg].vals());
    };
};
