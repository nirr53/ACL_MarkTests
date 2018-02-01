package ReadXMLFile;

import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.DocumentBuilder;
import org.w3c.dom.Document;
import org.w3c.dom.NodeList;
import org.w3c.dom.Node;
import org.w3c.dom.Element;
import java.io.File;

public class ReadXMLFile {

  public static void main(String argv[]) {

    try {

	File fXmlFile = new File("C:\\Users\\nirk\\Desktop\\myEclipseProjects\\ACL_MarkTests\\inputTestsResults\\OVOC IPP Manager 7.4.2000.xml");
	DocumentBuilderFactory dbFactory = DocumentBuilderFactory.newInstance();
	DocumentBuilder dBuilder = dbFactory.newDocumentBuilder();
	Document doc = dBuilder.parse(fXmlFile);
	doc.getDocumentElement().normalize();

	System.out.println("Root element : " + doc.getDocumentElement().getNodeName());
	System.out.println("Root project path : " + doc.getDocumentElement().getAttribute("projectPath"));

	NodeList nList = doc.getElementsByTagName("section");
	
	
	Node nNode0 = nList.item(0);
	Element eElement0 = (Element) nNode0;
	System.out.println("path - " + eElement0.getAttribute("projectPath"));
	System.out.println("----------------------------");

	for (int temp = 0; temp < nList.getLength(); temp++) {

		Node nNode = nList.item(temp);
		if (nNode.getNodeType() == Node.ELEMENT_NODE) {

			Element eElement = (Element) nNode;
			System.out.println("  secName: " + eElement.getAttribute("secName"));
			
			NodeList nList2 = eElement.getElementsByTagName("test");
			for (int temp2 = 0; temp2 < nList2.getLength(); temp2++) {
				
				if (nNode.getNodeType() == Node.ELEMENT_NODE) {
				
					Node nNode2 = nList2.item(temp2);
					Element eElement2 = (Element) nNode2;
					System.out.println("    testName: "   + eElement2.getAttribute("testName"));
					System.out.println("    testMark: "   + eElement2.getAttribute("testMark"));
					System.out.println("    testResult: " + eElement2.getAttribute("testResult"));
				}
	
			}
		}
	}
    } catch (Exception e) {
	e.printStackTrace();
    }
  }

}