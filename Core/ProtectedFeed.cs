using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

namespace BeyondModManager {
 internal static class ProtectedFeed {
  // These keys conceal public addresses in local files. Only the publisher holds the RSA signing key.
  const string EnvelopeKey = "5ycUaCYeUQPCHhgV839VR7ksYzq9isIvidr0E+wJV6arZWPblUVU9jfO2dPAJ9tYX6/ijGr0d5lv3GqqAL2Xdg==";
  const string Publisher = "<RSAKeyValue><Modulus>9Y1xjVW2cM/hBINfN865HWTY8UzwAjexAmAx4Q7wphQ6M3+uZ225ebUYXtu5znqVxg3HRGxPp/PKBOsjCz2f/rBL3wXCmeeJ6lHJJznFmPNr/ypeqlaBxyH9G4drTOyFHThwuG5CI2+7YqOS9gKXgjYBvPQ58QJiaaohks2glMfVW0gAvIVl2zzVQUBA0Bwraih0bCvTsRN9MBfNulmN9rcuwRBMsqAKj/orLipx9OxqMLB/v9ZjQcqO+vFw+EMEpwnNKfOGkyNToPwskI29Rv4d3xVicaBlZnqUY/aONR6YTHG+xXdUkKoEZVKP6B+owLTzOhdD4fFCubLy/9+ZdBZ7qFZKKgnd0iCIToFEBYC0AsQRZILg/LZvP7MDFzSt7JfWtqBaZuk2Pa/BMswWpTfrkrBnfYtdWLkGjsJYosBA6UZljsmTZdkBSa8DSww0gnpdqQ+hW0y92mLH+ylbNjYVqhFQNnD1VpEq2HN3Di1mYzDRkPqI6XP8TDJGyIdR</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>";
  internal static string Open(string value) {
   if (value == null || value.Length > 1024 || !value.StartsWith("bmm1.",StringComparison.Ordinal)) throw new InvalidDataException("Invalid update feed.");
   var data=Convert.FromBase64String(value.Substring(5));
   if(data.Length<64 || (data.Length-48)%16!=0)throw new InvalidDataException("Invalid update feed size.");
   var key=Convert.FromBase64String(EnvelopeKey);var aesKey=new byte[32];var authKey=new byte[32];var iv=new byte[16];
   Buffer.BlockCopy(key,0,aesKey,0,32);Buffer.BlockCopy(key,32,authKey,0,32);Buffer.BlockCopy(data,0,iv,0,16);
   int end=data.Length-32;
   using(var mac=new HMACSHA256(authKey)){var tag=mac.ComputeHash(data,0,end);int difference=0;for(int i=0;i<tag.Length;i++)difference|=tag[i]^data[end+i];if(difference!=0)throw new InvalidDataException("Damaged update feed.");}
   using(var aes=Aes.Create()){aes.Key=aesKey;aes.IV=iv;using(var transform=aes.CreateDecryptor())return new UTF8Encoding(false,true).GetString(transform.TransformFinalBlock(data,16,end-16));}
  }

  internal static bool AllowsTool(string target,string source,string hash,Dictionary<string,ZipArchiveEntry> files) {
   string directory=GameInstallation.ModsRoot+"/MixTapeMaker/bin/";
   if(!target.StartsWith(directory,StringComparison.OrdinalIgnoreCase))return false;
   var name=target.Substring(directory.Length).ToLowerInvariant();
   if(name!="deno.exe"&&name!="yt-dlp.exe"&&name!="tapeaudio.exe"&&name!="playlistfile.exe")return false;
   ZipArchiveEntry signature;
   if(!files.TryGetValue(source+".sig",out signature)||signature.Length!=384)return false;
   using(var input=signature.Open())using(var bytes=new MemoryStream())using(var rsa=new RSACryptoServiceProvider(new CspParameters(24))){
    rsa.PersistKeyInCsp=false;rsa.FromXmlString(Publisher);input.CopyTo(bytes);
    var message=Encoding.UTF8.GetBytes("MixTapeMaker/bin/"+name+"|"+hash.ToLowerInvariant());
    return rsa.VerifyData(message,"SHA256",bytes.ToArray());
   }
  }
 }
}